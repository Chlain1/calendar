import Foundation
import SwiftData

@MainActor
@Observable
final class SyncManager {

    var isSyncing = false
    var lastSyncDate: Date?
    var lastError: String?

    private let modelContext: ModelContext
    private let parser = ICalParser()
    private let serializer = ICalSerializer()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let accounts = try modelContext.fetch(FetchDescriptor<CalendarAccount>())
            for account in accounts where account.isEnabled {
                try await syncAccount(account)
            }
            lastSyncDate = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Account sync

    private func syncAccount(_ account: CalendarAccount) async throws {
        let password = Keychain.load(account: account.username + "@" + account.serverURL) ?? ""
        guard let url = URL(string: account.serverURL) else { throw CalDAVError.invalidURL }
        let client = CalDAVClient(serverURL: url, username: account.username, password: password)

        // Discover principal / home set if not cached
        if account.principalURL == nil {
            let principal = try await client.discoverPrincipalURL()
            account.principalURL = principal.absoluteString
        }
        guard let principalURLStr = account.principalURL, let principalURL = URL(string: principalURLStr) else { return }

        if account.calendarHomeSetURL == nil {
            let homeSet = try await client.discoverCalendarHomeSet(principalURL: principalURL)
            account.calendarHomeSetURL = homeSet.absoluteString
        }
        guard let homeSetStr = account.calendarHomeSetURL, let homeSetURL = URL(string: homeSetStr) else { return }

        // Discover/update collections
        let serverCals = try await client.listCalendars(homeSetURL: homeSetURL)
        updateCollections(account: account, serverCals: serverCals)

        // Push dirty/deleted events first
        for collection in account.collections where collection.isEnabled {
            guard let calURL = URL(string: collection.href, relativeTo: url)?.absoluteURL else { continue }
            try await pushLocalChanges(client: client, calendarURL: calURL, calendarHref: collection.href)
        }

        // Pull remote changes
        for collection in account.collections where collection.isEnabled {
            guard let calURL = URL(string: collection.href, relativeTo: url)?.absoluteURL else { continue }
            try await pullRemoteChanges(client: client, calendarURL: calURL, collection: collection)
        }

        try modelContext.save()
    }

    // MARK: - Collection management

    private func updateCollections(account: CalendarAccount, serverCals: [CalDAVCalendar]) {
        let serverHrefs = Set(serverCals.map(\.href))

        // Remove deleted
        account.collections.removeAll { !serverHrefs.contains($0.href) }

        // Add new / update existing
        for cal in serverCals {
            if let existing = account.collections.first(where: { $0.href == cal.href }) {
                existing.displayName = cal.displayName
                if let c = cal.colorHex { existing.colorHex = c }
            } else {
                let col = CalendarCollection(href: cal.href, displayName: cal.displayName, accountID: account.id, colorHex: cal.colorHex)
                account.collections.append(col)
                modelContext.insert(col)
            }
        }
    }

    // MARK: - Push

    private func pushLocalChanges(client: CalDAVClient, calendarURL: URL, calendarHref: String) async throws {
        let desc = FetchDescriptor<CalendarEvent>(predicate: #Predicate { ev in
            ev.calendarHref == calendarHref && (ev.isDirty || ev.isDeleted)
        })
        let dirty = try modelContext.fetch(desc)

        for event in dirty {
            if event.isDeleted {
                if let href = event.href {
                    try? await client.deleteEvent(href: href)
                }
                modelContext.delete(event)
            } else {
                let ics = serializer.serialize(event: event)
                if let newEtag = try? await client.putEvent(calendarURL: calendarURL, event: event, icsData: ics) {
                    event.etag = newEtag
                }
                if event.href == nil {
                    event.href = calendarURL.appendingPathComponent("\(event.uid).ics").absoluteString
                }
                event.isDirty = false
            }
        }
    }

    // MARK: - Pull

    private func pullRemoteChanges(client: CalDAVClient, calendarURL: URL, collection: CalendarCollection) async throws {
        // Check if ctag changed
        let remoteCTag = try? await client.fetchCTag(calendarURL: calendarURL)
        if let remote = remoteCTag, remote == collection.ctag { return } // Nothing changed

        // Fetch all event stubs (href + etag)
        let from = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let to = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
        let stubs = try await client.fetchEventStubs(calendarURL: calendarURL, from: from, to: to)

        // Load local events for this calendar
        let calHref = collection.href
        let desc = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.calendarHref == calHref })
        let localEvents = try modelContext.fetch(desc)
        let localByHref = Dictionary(uniqueKeysWithValues: localEvents.compactMap { e -> (String, CalendarEvent)? in
            guard let h = e.href else { return nil }
            return (h, e)
        })

        let remoteHrefs = Set(stubs.map(\.href))

        // Delete events no longer on server (that we haven't modified)
        for local in localEvents {
            if let href = local.href, !remoteHrefs.contains(href), !local.isDirty {
                modelContext.delete(local)
            }
        }

        // Find events that need fetching (new or changed etag)
        let hrefs = stubs.compactMap { stub -> String? in
            if let local = localByHref[stub.href], local.etag == stub.etag { return nil }
            return stub.href
        }

        // Fetch in batches of 50
        for batch in hrefs.chunked(by: 50) {
            let fetched = try await client.fetchEvents(calendarURL: calendarURL, hrefs: batch)
            for item in fetched {
                let parsed = parser.parse(icsString: item.icsData)
                for icalEv in parsed {
                    upsertEvent(icalEv, href: item.href, etag: item.etag, calendarHref: collection.href, colorHex: collection.colorHex)
                }
            }
        }

        collection.ctag = remoteCTag
    }

    // MARK: - Upsert

    private func upsertEvent(_ ical: ICalEvent, href: String, etag: String, calendarHref: String, colorHex: String?) {
        let uid = ical.uid
        let desc = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.uid == uid })
        let existing = try? modelContext.fetch(desc).first

        if let ev = existing {
            guard !ev.isDirty else { return } // Don't overwrite local unsent changes
            ev.title = ical.summary.isEmpty ? "(No title)" : ical.summary
            ev.startDate = ical.dtstart ?? Date()
            ev.endDate = ical.dtend ?? Date()
            ev.isAllDay = ical.isAllDay
            ev.notes = ical.description
            ev.location = ical.location
            ev.etag = etag
            ev.href = href
            ev.colorHex = colorHex
            ev.modifiedAt = Date()
        } else {
            let ev = CalendarEvent(
                title: ical.summary.isEmpty ? "(No title)" : ical.summary,
                startDate: ical.dtstart ?? Date(),
                endDate: ical.dtend ?? Date(),
                isAllDay: ical.isAllDay,
                notes: ical.description,
                location: ical.location
            )
            ev.uid = ical.uid
            ev.etag = etag
            ev.href = href
            ev.calendarHref = calendarHref
            ev.colorHex = colorHex
            ev.isDirty = false
            modelContext.insert(ev)
        }
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
