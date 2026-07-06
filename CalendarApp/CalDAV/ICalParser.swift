import Foundation

struct ICalEvent {
    var uid: String = ""
    var summary: String = ""
    var description: String?
    var location: String?
    var dtstart: Date?
    var dtend: Date?
    var duration: TimeInterval?
    var isAllDay: Bool = false
    var etag: String?
    var href: String?
}

final class ICalParser {

    func parse(icsString: String) -> [ICalEvent] {
        let unfolded = unfold(icsString)
        let lines = unfolded.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        var events: [ICalEvent] = []
        var current: ICalEvent?

        for line in lines {
            if line.hasPrefix("BEGIN:VEVENT") {
                current = ICalEvent()
            } else if line.hasPrefix("END:VEVENT"), var ev = current {
                // Resolve DTEND from DURATION if missing
                if ev.dtend == nil, let start = ev.dtstart, let dur = ev.duration {
                    ev.dtend = start.addingTimeInterval(dur)
                }
                if ev.dtend == nil, let start = ev.dtstart {
                    ev.dtend = ev.isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: start) : start.addingTimeInterval(3600)
                }
                events.append(ev)
                current = nil
            } else if var ev = current {
                let (name, params, value) = parseLine(line)
                switch name {
                case "UID":
                    ev.uid = value
                case "SUMMARY":
                    ev.summary = unescape(value)
                case "DESCRIPTION":
                    ev.description = unescape(value)
                case "LOCATION":
                    ev.location = unescape(value)
                case "DTSTART":
                    let tzid = params["TZID"]
                    (ev.dtstart, ev.isAllDay) = parseDate(value, tzid: tzid)
                case "DTEND":
                    let tzid = params["TZID"]
                    (ev.dtend, _) = parseDate(value, tzid: tzid)
                case "DURATION":
                    ev.duration = parseDuration(value)
                default:
                    break
                }
                current = ev
            }
        }
        return events
    }

    // MARK: - Private helpers

    private func unfold(_ text: String) -> String {
        // RFC 5545: lines may be folded with CRLF + whitespace
        var result = text.replacingOccurrences(of: "\r\n ", with: "")
        result = result.replacingOccurrences(of: "\r\n\t", with: "")
        result = result.replacingOccurrences(of: "\n ", with: "")
        result = result.replacingOccurrences(of: "\n\t", with: "")
        return result
    }

    private func parseLine(_ line: String) -> (name: String, params: [String: String], value: String) {
        guard let colonIdx = line.firstIndex(of: ":") else { return (line, [:], "") }
        let nameAndParams = String(line[line.startIndex..<colonIdx])
        let value = String(line[line.index(after: colonIdx)...])

        let parts = nameAndParams.components(separatedBy: ";")
        let name = parts[0].uppercased()
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
        }
        return (name, params, value)
    }

    private func parseDate(_ value: String, tzid: String?) -> (Date?, Bool) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // All-day: YYYYMMDD (no T)
        if trimmed.count == 8 && !trimmed.contains("T") {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.timeZone = TimeZone(identifier: "UTC")
            return (fmt.date(from: trimmed), true)
        }
        // UTC datetime: YYYYMMDDTHHmmssZ
        if trimmed.hasSuffix("Z") {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            fmt.timeZone = TimeZone(identifier: "UTC")
            return (fmt.date(from: trimmed), false)
        }
        // Floating or TZID datetime
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        if let tz = tzid, let zone = TimeZone(identifier: tz) {
            fmt.timeZone = zone
        } else {
            fmt.timeZone = .current
        }
        return (fmt.date(from: trimmed), false)
    }

    private func parseDuration(_ value: String) -> TimeInterval {
        // Simplified: P[n]DT[n]H[n]M[n]S and P[n]W
        var s: TimeInterval = 0
        var v = value
        let negative = v.hasPrefix("-")
        if negative { v = String(v.dropFirst()) }
        if v.hasPrefix("P") { v = String(v.dropFirst()) }

        var current = ""
        for ch in v {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                let n = Double(current) ?? 0
                switch ch {
                case "W": s += n * 7 * 86400
                case "D": s += n * 86400
                case "H": s += n * 3600
                case "M": s += n * 60
                case "S": s += n
                default: break
                }
                current = ""
            }
        }
        return negative ? -s : s
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

