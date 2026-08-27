import SwiftUI
import SwiftData

@Observable
final class CalendarViewModel {

    var currentWeekStart: Date
    var selectedDate: Date?
    var selectedEvent: CalendarEvent?
    var showingAddEvent = false
    var showingEventDetail = false
    var newEventStartDate: Date = Date()

    private let calendar: Calendar

    init() {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        self.calendar = cal
        self.currentWeekStart = Self.startOfWeek(for: Date(), calendar: cal)
    }

    // MARK: - Week navigation

    var weekDays: [Date] {
        (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: currentWeekStart)!
        }
    }

    private static let weekTitleFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()

    var weekTitle: String {
        // Use the month that contains most days of the week
        let midWeek = calendar.date(byAdding: .day, value: 3, to: currentWeekStart)!
        return Self.weekTitleFormatter.string(from: midWeek)
    }

    var weekNumber: Int {
        calendar.component(.weekOfYear, from: currentWeekStart)
    }

    func goToNextWeek() {
        currentWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart)!
    }

    func goToPreviousWeek() {
        currentWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
    }

    func goToToday() {
        currentWeekStart = Self.startOfWeek(for: Date(), calendar: calendar)
    }

    var isCurrentWeek: Bool {
        let todayWeek = Self.startOfWeek(for: Date(), calendar: calendar)
        return calendar.isDate(currentWeekStart, inSameDayAs: todayWeek)
    }

    // MARK: - Event filtering

    func events(for date: Date, from allEvents: [CalendarEvent]) -> [CalendarEvent] {
        allEvents.filter { event in
            !event.isDeleted && !event.isAllDay && calendar.isDate(event.startDate, inSameDayAs: date)
        }.sorted { $0.startDate < $1.startDate }
    }

    func allDayEvents(for date: Date, from allEvents: [CalendarEvent]) -> [CalendarEvent] {
        allEvents.filter { event in
            !event.isDeleted && event.isAllDay && eventOccurs(on: date, event: event)
        }
    }

    private func eventOccurs(on date: Date, event: CalendarEvent) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return event.startDate < dayEnd && event.endDate > dayStart
    }

    func eventsInWeek(_ allEvents: [CalendarEvent]) -> [CalendarEvent] {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) else { return [] }
        return allEvents.filter { !$0.isDeleted && $0.startDate >= currentWeekStart && $0.startDate < weekEnd }
    }

    // MARK: - Tap handling

    func tapOnTimeSlot(date: Date, hour: Int) {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        newEventStartDate = calendar.date(from: comps) ?? Date()
        showingAddEvent = true
    }

    func tapOnEvent(_ event: CalendarEvent) {
        selectedEvent = event
        showingEventDetail = true
    }

    // MARK: - Helpers

    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private static let dayLabelFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt
    }()

    func dayLabel(for date: Date) -> String {
        Self.dayLabelFormatter.string(from: date).uppercased()
    }

    func dayNumber(for date: Date) -> String {
        Self.dayNumberFormatter.string(from: date)
    }
}
