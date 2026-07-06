import SwiftUI
import SwiftData
import Foundation

@Model
final class CalendarEvent {
    var id: UUID
    var uid: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var notes: String?
    var location: String?
    var etag: String?
    var href: String?
    var calendarHref: String?
    var colorHex: String?
    var eventKitIdentifier: String?
    var isDirty: Bool
    var isDeleted: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.id = UUID()
        self.uid = "\(UUID().uuidString)@CalendarApp"
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.notes = notes
        self.location = location
        self.isDirty = true
        self.isDeleted = false
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    var color: Color { Color(hex: colorHex ?? "#4A90D9") ?? .blue }
    var isFromEventKit: Bool { eventKitIdentifier != nil }
}

extension CalendarEvent: Identifiable {}
