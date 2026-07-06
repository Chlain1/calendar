import Foundation

enum CalDAVError: Error, LocalizedError {
    case invalidURL
    case authenticationFailed
    case serverError(Int)
    case noCalendarHomeSet
    case parseError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .authenticationFailed: return "Authentication failed — check your credentials"
        case .serverError(let code): return "Server returned HTTP \(code)"
        case .noCalendarHomeSet: return "Could not find calendar home on server"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .networkError(let err): return err.localizedDescription
        }
    }
}

struct CalDAVCalendar {
    var href: String
    var displayName: String
    var ctag: String?
    var colorHex: String?
}

struct CalDAVEventStub {
    var href: String
    var etag: String
}

struct CalDAVEventData {
    var href: String
    var etag: String
    var icsData: String
}

final class CalDAVClient: NSObject {

    let serverURL: URL
    let username: String
    private let password: String
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(serverURL: URL, username: String, password: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
    }

    // MARK: - Discovery

    func discoverPrincipalURL() async throws -> URL {
        // Try well-known first
        let wellKnown = serverURL.appendingPathComponent(".well-known/caldav")
        let (_, resp) = try await request(method: "GET", url: wellKnown, body: nil, headers: [:])
        let effectiveURL: URL
        if let http = resp as? HTTPURLResponse, (301...308).contains(http.statusCode),
           let loc = http.value(forHTTPHeaderField: "Location"), let locURL = URL(string: loc) {
            effectiveURL = locURL
        } else {
            effectiveURL = wellKnown
        }

        // PROPFIND for current-user-principal
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop><d:current-user-principal/></d:prop>
        </d:propfind>
        """
        let (data, _) = try await propfind(url: effectiveURL, body: xml, depth: "0")
        let root = try SimpleXMLParser().parse(data: data)
        let href = root.firstDescendant(localName: "href", after: "current-user-principal")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let href, !href.isEmpty else { throw CalDAVError.noCalendarHomeSet }
        guard let url = URL(string: href, relativeTo: serverURL)?.absoluteURL else { throw CalDAVError.invalidURL }
        return url
    }

    func discoverCalendarHomeSet(principalURL: URL) async throws -> URL {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><c:calendar-home-set/></d:prop>
        </d:propfind>
        """
        let (data, _) = try await propfind(url: principalURL, body: xml, depth: "0")
        let root = try SimpleXMLParser().parse(data: data)
        let href = root.firstDescendant(localName: "href", after: "calendar-home-set")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let href, !href.isEmpty else { throw CalDAVError.noCalendarHomeSet }
        guard let url = URL(string: href, relativeTo: serverURL)?.absoluteURL else { throw CalDAVError.invalidURL }
        return url
    }

    func listCalendars(homeSetURL: URL) async throws -> [CalDAVCalendar] {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:ic="http://apple.com/ns/ical/">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
            <cs:getctag/>
            <ic:calendar-color/>
            <c:supported-calendar-component-set/>
          </d:prop>
        </d:propfind>
        """
        let (data, _) = try await propfind(url: homeSetURL, body: xml, depth: "1")
        let root = try SimpleXMLParser().parse(data: data)
        var calendars: [CalDAVCalendar] = []

        for response in root.descendants(localName: "response") {
            // Must have resourcetype containing "calendar"
            guard response.firstDescendant(localName: "calendar") != nil else { continue }
            // Must support VEVENT
            let comps = response.descendants(localName: "comp").map { $0.attribute("name") ?? "" }
            guard comps.isEmpty || comps.contains("VEVENT") else { continue }

            guard let href = response.firstDescendant(localName: "href")?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty else { continue }
            let displayName = response.firstDescendant(localName: "displayname")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? href
            let ctag = response.firstDescendant(localName: "getctag")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var color = response.firstDescendant(localName: "calendar-color")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let c = color, c.count == 9 { color = String(c.prefix(7)) } // strip alpha

            calendars.append(CalDAVCalendar(href: href, displayName: displayName, ctag: ctag, colorHex: color))
        }
        return calendars
    }

    // MARK: - Events

    func fetchEventStubs(calendarURL: URL, from: Date? = nil, to: Date? = nil) async throws -> [CalDAVEventStub] {
        var timeRange = ""
        if let from, let to {
            let fmt = isoFmt()
            timeRange = """
            <c:time-range start="\(fmt.string(from: from))" end="\(fmt.string(from: to))"/>
            """
        }
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><d:getetag/></d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="VEVENT">\(timeRange)</c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """
        let (data, _) = try await report(url: calendarURL, body: xml)
        let root = try SimpleXMLParser().parse(data: data)
        return root.descendants(localName: "response").compactMap { resp -> CalDAVEventStub? in
            guard let href = resp.firstDescendant(localName: "href")?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  let etag = resp.firstDescendant(localName: "getetag")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }
            return CalDAVEventStub(href: href, etag: etag.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
    }

    func fetchEvents(calendarURL: URL, hrefs: [String]) async throws -> [CalDAVEventData] {
        guard !hrefs.isEmpty else { return [] }
        let hrefElements = hrefs.map { "<d:href>\($0)</d:href>" }.joined(separator: "\n    ")
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <c:calendar-data/>
          </d:prop>
          \(hrefElements)
        </c:calendar-multiget>
        """
        let (data, _) = try await report(url: calendarURL, body: xml)
        let root = try SimpleXMLParser().parse(data: data)
        return root.descendants(localName: "response").compactMap { resp -> CalDAVEventData? in
            guard let href = resp.firstDescendant(localName: "href")?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  let icsData = resp.firstDescendant(localName: "calendar-data")?.text
            else { return nil }
            let etag = resp.firstDescendant(localName: "getetag")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CalDAVEventData(href: href, etag: etag.trimmingCharacters(in: CharacterSet(charactersIn: "\"")), icsData: icsData)
        }
    }

    func putEvent(calendarURL: URL, event: CalendarEvent, icsData: String) async throws -> String? {
        let eventURL = event.href.flatMap { URL(string: $0, relativeTo: serverURL)?.absoluteURL }
            ?? calendarURL.appendingPathComponent("\(event.uid).ics")
        var headers: [String: String] = ["Content-Type": "text/calendar; charset=utf-8"]
        if let etag = event.etag { headers["If-Match"] = "\"\(etag)\"" }
        let (_, resp) = try await request(method: "PUT", url: eventURL, body: Data(icsData.utf8), headers: headers)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 412 { throw CalDAVError.serverError(412) }
            if !(200..<300).contains(http.statusCode) { throw CalDAVError.serverError(http.statusCode) }
            return http.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    func deleteEvent(href: String) async throws {
        guard let url = URL(string: href, relativeTo: serverURL)?.absoluteURL else { throw CalDAVError.invalidURL }
        let (_, resp) = try await request(method: "DELETE", url: url, body: nil, headers: [:])
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode != 404 { throw CalDAVError.serverError(http.statusCode) }
        }
    }

    func fetchCTag(calendarURL: URL) async throws -> String? {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
          <d:prop><cs:getctag/></d:prop>
        </d:propfind>
        """
        let (data, _) = try await propfind(url: calendarURL, body: xml, depth: "0")
        let root = try SimpleXMLParser().parse(data: data)
        return root.firstDescendant(localName: "getctag")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTTP primitives

    private func propfind(url: URL, body: String, depth: String) async throws -> (Data, URLResponse) {
        let headers = ["Depth": depth, "Content-Type": "application/xml; charset=utf-8"]
        return try await request(method: "PROPFIND", url: url, body: Data(body.utf8), headers: headers)
    }

    private func report(url: URL, body: String) async throws -> (Data, URLResponse) {
        let headers = ["Depth": "1", "Content-Type": "application/xml; charset=utf-8"]
        return try await request(method: "REPORT", url: url, body: Data(body.utf8), headers: headers)
    }

    private func request(method: String, url: URL, body: Data?, headers: [String: String]) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.httpBody = body

        let creds = "\(username):\(password)"
        let encoded = Data(creds.utf8).base64EncodedString()
        req.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                throw CalDAVError.authenticationFailed
            }
            return (data, resp)
        } catch let e as CalDAVError {
            throw e
        } catch {
            throw CalDAVError.networkError(error)
        }
    }

    private func isoFmt() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }
}

// Accept self-signed certs for local servers (with user awareness via settings)
extension CalDAVClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Simple XML tree parser

final class XMLNode {
    let localName: String
    let namespaceURI: String?
    var attributes: [String: String]
    var text: String = ""
    var children: [XMLNode] = []
    weak var parent: XMLNode?

    init(localName: String, namespaceURI: String?, attributes: [String: String]) {
        self.localName = localName
        self.namespaceURI = namespaceURI
        self.attributes = attributes
    }

    func attribute(_ name: String) -> String? { attributes[name] }

    func descendants(localName name: String) -> [XMLNode] {
        var result: [XMLNode] = []
        if localName == name { result.append(self) }
        for child in children { result.append(contentsOf: child.descendants(localName: name)) }
        return result
    }

    func firstDescendant(localName name: String) -> XMLNode? {
        if localName == name { return self }
        for child in children { if let found = child.firstDescendant(localName: name) { return found } }
        return nil
    }

    /// Find first node with `targetName` that appears inside (or after) a node named `after`
    func firstDescendant(localName targetName: String, after parentName: String) -> XMLNode? {
        if let parent = firstDescendant(localName: parentName) {
            return parent.firstDescendant(localName: targetName)
        }
        return nil
    }
}

final class SimpleXMLParser: NSObject, XMLParserDelegate {
    private var root: XMLNode?
    private var current: XMLNode?

    func parse(data: Data) throws -> XMLNode {
        root = nil
        current = nil
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        if let err = parser.parserError { throw CalDAVError.parseError(err.localizedDescription) }
        guard let root else { throw CalDAVError.parseError("Empty XML") }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName _: String?, attributes: [String: String]) {
        let node = XMLNode(localName: elementName, namespaceURI: namespaceURI, attributes: attributes)
        node.parent = current
        current?.children.append(node)
        current = node
        if root == nil { root = node }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
        current = current?.parent
    }
}
