import Foundation
import EventKit
import SwiftData
import UIKit

/// Mirrors calendars and events from the device's Apple Calendar (EventKit) into the
/// app's own store, so they show up alongside CalDAV calendars in the week view.
///
/// Apple Calendar events are read-only inside this app (see `CalendarEvent.isFromEventKit`) —
/// edits belong in the system Calendar app, which avoids the pitfalls of writing back to
/// recurring EventKit events (occurrence identifiers aren't stable across edits).
@MainActor
@Observable
final class EventKitManager {

    /// Fixed id for the synthetic account that represents the device's Apple Calendar sources.
    static let accountID = UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!

    var authorizationStatus: EKAuthorizationStatus
    var isSyncing = false
    var lastSyncDate: Date?
    var lastError: String?

    private let eventStore = EKEventStore()
    private let modelContext: ModelContext
    private nonisolated(unsafe) var changeObserver: NSObjectProtocol?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        observeStoreChanges()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    private func observeStoreChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sync()
            }
        }
    }

    // MARK: - Authorization

    var isAuthorized: Bool { authorizationStatus == .fullAccess }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            lastError = error.localizedDescription
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    // MARK: - Sync

    func sync() async {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let account = fetchOrCreateAccount()
        guard account.isEnabled else { return }

        let ekCalendars = eventStore.calendars(for: .event)
        updateCollections(account: account, ekCalendars: ekCalendars)

        let from = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let to = Calendar.current.date(byAdding: .year, value: 2, to: Date())!

        for collection in account.collections where collection.isEnabled {
            guard let ekCal = ekCalendars.first(where: { $0.calendarIdentifier == collection.eventKitIdentifier }) else { continue }
            pullEvents(from: from, to: to, ekCalendar: ekCal, collection: collection)
        }

        do {
            try modelContext.save()
            lastSyncDate = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Account / collections

    private func fetchOrCreateAccount() -> CalendarAccount {
        let id = Self.accountID
        let desc = FetchDescriptor<CalendarAccount>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(desc).first {
            return existing
        }
        let account = CalendarAccount(name: "Apple Calendar", serverURL: "", username: "")
        account.id = id
        account.isEventKitAccount = true
        modelContext.insert(account)
        return account
    }

    private func updateCollections(account: CalendarAccount, ekCalendars: [EKCalendar]) {
        let ekIDs = Set(ekCalendars.map(\.calendarIdentifier))

        // Remove collections for calendars that no longer exist, and their mirrored events.
        let removed = account.collections.filter { col in
            guard let id = col.eventKitIdentifier else { return false }
            return !ekIDs.contains(id)
        }
        for col in removed {
            deleteEvents(forCalendarHref: col.href)
        }
        account.collections.removeAll { col in
            guard let id = col.eventKitIdentifier else { return false }
            return !ekIDs.contains(id)
        }

        for ekCal in ekCalendars {
            let colorHex = ekCal.cgColor.map { UIColor(cgColor: $0) }.map(hexString(from:))
            if let existing = account.collections.first(where: { $0.eventKitIdentifier == ekCal.calendarIdentifier }) {
                existing.displayName = ekCal.title
                if let colorHex { existing.colorHex = colorHex }
                existing.allowsModification = ekCal.allowsContentModifications
            } else {
                let col = CalendarCollection(
                    href: "eventkit://\(ekCal.calendarIdentifier)",
                    displayName: ekCal.title,
                    accountID: account.id,
                    colorHex: colorHex
                )
                col.eventKitIdentifier = ekCal.calendarIdentifier
                col.allowsModification = ekCal.allowsContentModifications
                account.collections.append(col)
                modelContext.insert(col)
            }
        }
    }

    private func hexString(from uiColor: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    // MARK: - Events

    private func pullEvents(from: Date, to: Date, ekCalendar: EKCalendar, collection: CalendarCollection) {
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: [ekCalendar])
        let ekEvents = eventStore.events(matching: predicate)

        let calendarHref = collection.href
        let desc = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.calendarHref == calendarHref })
        let localEvents = (try? modelContext.fetch(desc)) ?? []

        var localByKey: [String: CalendarEvent] = [:]
        for event in localEvents {
            if let id = event.eventKitIdentifier {
                localByKey[occurrenceKey(id, event.startDate)] = event
            }
        }

        var seenKeys = Set<String>()

        for ekEvent in ekEvents {
            guard let ekID = ekEvent.eventIdentifier else { continue }
            let key = occurrenceKey(ekID, ekEvent.startDate)
            seenKeys.insert(key)

            if let existing = localByKey[key] {
                apply(ekEvent, to: existing, colorHex: collection.colorHex)
            } else {
                let newEvent = CalendarEvent(
                    title: title(for: ekEvent),
                    startDate: ekEvent.startDate,
                    endDate: ekEvent.endDate ?? ekEvent.startDate.addingTimeInterval(3600),
                    isAllDay: ekEvent.isAllDay,
                    notes: ekEvent.notes,
                    location: ekEvent.location
                )
                newEvent.eventKitIdentifier = ekID
                newEvent.calendarHref = calendarHref
                newEvent.colorHex = collection.colorHex
                newEvent.isDirty = false
                modelContext.insert(newEvent)
            }
        }

        // Drop mirrored events that are no longer present upstream (deleted/out of range).
        for event in localEvents {
            guard let id = event.eventKitIdentifier else { continue }
            if !seenKeys.contains(occurrenceKey(id, event.startDate)) {
                modelContext.delete(event)
            }
        }
    }

    private func deleteEvents(forCalendarHref href: String) {
        let desc = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.calendarHref == href })
        guard let events = try? modelContext.fetch(desc) else { return }
        for event in events { modelContext.delete(event) }
    }

    private func title(for ekEvent: EKEvent) -> String {
        guard let title = ekEvent.title, !title.isEmpty else { return "(No title)" }
        return title
    }

    private func apply(_ ekEvent: EKEvent, to event: CalendarEvent, colorHex: String?) {
        event.title = title(for: ekEvent)
        event.startDate = ekEvent.startDate
        event.endDate = ekEvent.endDate ?? ekEvent.startDate.addingTimeInterval(3600)
        event.isAllDay = ekEvent.isAllDay
        event.notes = ekEvent.notes
        event.location = ekEvent.location
        event.colorHex = colorHex
        event.modifiedAt = Date()
    }

    private func occurrenceKey(_ eventIdentifier: String, _ date: Date) -> String {
        "\(eventIdentifier)#\(Int(date.timeIntervalSince1970))"
    }
}
