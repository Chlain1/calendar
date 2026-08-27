import XCTest
@testable import CalendarApp

final class ICalParserTests: XCTestCase {
    private let parser = ICalParser()

    func testParseAllDayEventWithEscapedValues() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:all-day-1
        DTSTART;VALUE=DATE:20240115
        DTEND;VALUE=DATE:20240117
        SUMMARY:Team\\, Berlin
        DESCRIPTION:Line 1\\nLine 2
        LOCATION:Berlin\\; HQ
        END:VEVENT
        END:VCALENDAR
        """

        let events = parser.parse(icsString: ics)
        XCTAssertEqual(events.count, 1)

        let event = events[0]
        XCTAssertEqual(event.uid, "all-day-1")
        XCTAssertEqual(event.summary, "Team, Berlin")
        XCTAssertEqual(event.description, "Line 1\nLine 2")
        XCTAssertEqual(event.location, "Berlin; HQ")
        XCTAssertTrue(event.isAllDay)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.date(from: "2024-01-15T00:00:00Z")
        let end = formatter.date(from: "2024-01-17T00:00:00Z")
        XCTAssertEqual(event.dtstart, start)
        XCTAssertEqual(event.dtend, end)
    }

    func testParseTimedEventAndDurationFallback() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:timed-2
        DTSTART:20240115T090000Z
        DURATION:P1DT2H30M
        SUMMARY:Kickoff
        END:VEVENT
        END:VCALENDAR
        """

        let events = parser.parse(icsString: ics)
        XCTAssertEqual(events.count, 1)

        let event = events[0]
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.summary, "Kickoff")
        XCTAssertEqual(event.duration, 95400.0, accuracy: 0.1)
        XCTAssertNotNil(event.dtstart)
        XCTAssertNotNil(event.dtend)

        let expectedEnd = event.dtstart!.addingTimeInterval(95400)
        XCTAssertEqual(event.dtend!, expectedEnd, accuracy: 0.1)
    }

    func testParseFoldedLineIsUnfolded() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:folded-1
        SUMMARY:This is a very long summary that is folded\r\n across lines
        DTSTART:20240115T100000Z
        DTEND:20240115T110000Z
        END:VEVENT
        END:VCALENDAR
        """

        let events = parser.parse(icsString: ics)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].summary.contains("folded"))
        XCTAssertTrue(events[0].summary.contains("across"))
        XCTAssertTrue(events[0].summary.contains("lines"))
    }

    func testParseDateWithoutDtEndUsesOneHourFallback() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:no-end-1
        DTSTART:20240115T090000Z
        SUMMARY:Fallback test
        END:VEVENT
        END:VCALENDAR
        """

        let event = parser.parse(icsString: ics)[0]
        XCTAssertNotNil(event.dtend)
        XCTAssertEqual(event.dtend!.timeIntervalSince(event.dtstart!), 3600, accuracy: 0.1)
    }
}

final class ICalSerializerTests: XCTestCase {
    func testSerializeAllDayEventUsesDateFormat() {
        let start = dateFromISO("2024-01-15T00:00:00Z")
        let end = dateFromISO("2024-01-17T00:00:00Z")

        let event = CalendarEvent(title: "Trip", startDate: start, endDate: end, isAllDay: true)
        event.uid = "evt-all-day"
        event.notes = "Holiday\nPlan"
        event.location = "Paris; France"

        let ics = ICalSerializer().serialize(event: event)

        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("BEGIN:VEVENT"))
        XCTAssertTrue(ics.contains("UID:evt-all-day"))
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20240115"))
        XCTAssertTrue(ics.contains("DTEND;VALUE=DATE:20240117"))
        XCTAssertTrue(ics.contains("SUMMARY:Trip"))
        XCTAssertTrue(ics.contains("DESCRIPTION:Holiday\\nPlan"))
        XCTAssertTrue(ics.contains("LOCATION:Paris\\; France"))
        XCTAssertTrue(ics.hasSuffix("\r\n"))
    }

    func testSerializeTimedEventIncludesExpectedFields() {
        let start = dateFromISO("2024-01-20T10:00:00Z")
        let end = dateFromISO("2024-01-20T11:30:00Z")

        let event = CalendarEvent(title: "Sprint review", startDate: start, endDate: end)
        event.uid = "evt-timed"
        event.notes = "Follow up, action items"
        event.location = "Room 1"

        let ics = ICalSerializer().serialize(event: event)
        XCTAssertTrue(ics.contains("DTSTART:20240120T100000Z"))
        XCTAssertTrue(ics.contains("DTEND:20240120T113000Z"))
        XCTAssertTrue(ics.contains("SUMMARY:Sprint review"))
        XCTAssertTrue(ics.contains("DESCRIPTION:Follow up\\, action items"))
        XCTAssertTrue(ics.contains("LOCATION:Room 1"))
    }

    func testSerializeFoldsLongLines() {
        let start = dateFromISO("2024-03-01T09:00:00Z")
        let end = dateFromISO("2024-03-01T10:00:00Z")

        let event = CalendarEvent(title: String(repeating: "A", count: 200), startDate: start, endDate: end)
        event.uid = "evt-long"

        let ics = ICalSerializer().serialize(event: event)
        XCTAssertTrue(ics.contains("\r\n "))
        XCTAssertTrue(ics.contains("SUMMARY:" + String(repeating: "A", count: 200)))
    }

    private func dateFromISO(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }
}

final class ColorHexTests: XCTestCase {
    func testColorHexInitAcceptsRGBAndRRGGBBAA() {
        let rgb = Color(hex: "#FF00AA")
        XCTAssertNotNil(rgb)

        let rgba = Color(hex: "#11223344")
        XCTAssertNotNil(rgba)
    }

    func testColorHexStringReturnsCanonicalHex() {
        let color = Color(hex: "#00FF00")!
        XCTAssertEqual(color.hexString, "#00FF00")
    }

    func testColorHexRejectsInvalidValues() {
        XCTAssertNil(Color(hex: "#GGGGGG"))
        XCTAssertNil(Color(hex: "#12345"))
    }
}

final class CalendarModelTests: XCTestCase {
    func testCalendarEventDefaultProperties() {
        let start = dateFromISO("2024-06-01T09:00:00Z")
        let end = dateFromISO("2024-06-01T10:00:00Z")

        let event = CalendarEvent(title: "Demo", startDate: start, endDate: end)

        XCTAssertFalse(event.uid.isEmpty)
        XCTAssertEqual(event.title, "Demo")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate, end)
        XCTAssertEqual(event.duration, 3600)
        XCTAssertTrue(event.isDirty)
        XCTAssertFalse(event.isDeleted)
        XCTAssertFalse(event.isFromEventKit)
        XCTAssertEqual(event.color, Color(hex: "#4A90D9") ?? .blue)
    }

    func testCalendarCollectionDefaultProperties() {
        let accountID = UUID()
        let collection = CalendarCollection(href: "/caldav/test.ics", displayName: "Work", accountID: accountID, colorHex: "#FF1493")

        XCTAssertEqual(collection.href, "/caldav/test.ics")
        XCTAssertEqual(collection.displayName, "Work")
        XCTAssertEqual(collection.accountID, accountID)
        XCTAssertTrue(collection.isEnabled)
        XCTAssertTrue(collection.allowsModification)
        XCTAssertFalse(collection.isFromEventKit)
        XCTAssertEqual(collection.color.hexString, "#FF1493")
    }

    func testCalendarAccountDefaultProperties() {
        let account = CalendarAccount(name: "Demo", serverURL: "https://example.com", username: "tester")

        XCTAssertEqual(account.name, "Demo")
        XCTAssertEqual(account.serverURL, "https://example.com")
        XCTAssertEqual(account.username, "tester")
        XCTAssertTrue(account.isEnabled)
        XCTAssertFalse(account.isEventKitAccount)
        XCTAssertTrue(account.collections.isEmpty)
    }

    private func dateFromISO(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }
}
