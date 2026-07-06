import Foundation

final class ICalSerializer {

    func serialize(event: CalendarEvent) -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCALENDAR")
        lines.append("VERSION:2.0")
        lines.append("PRODID:-//CalendarApp//CalendarApp 1.0//EN")
        lines.append("CALSCALE:GREGORIAN")
        lines.append("BEGIN:VEVENT")
        lines.append("UID:\(event.uid)")
        lines.append("DTSTAMP:\(formatUTC(Date()))")

        if event.isAllDay {
            lines.append("DTSTART;VALUE=DATE:\(formatDate(event.startDate))")
            lines.append("DTEND;VALUE=DATE:\(formatDate(event.endDate))")
        } else {
            lines.append("DTSTART:\(formatUTC(event.startDate))")
            lines.append("DTEND:\(formatUTC(event.endDate))")
        }

        lines.append("SUMMARY:\(escape(event.title))")
        if let notes = event.notes, !notes.isEmpty {
            lines.append("DESCRIPTION:\(escape(notes))")
        }
        if let location = event.location, !location.isEmpty {
            lines.append("LOCATION:\(escape(location))")
        }
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")

        return fold(lines.joined(separator: "\r\n")) + "\r\n"
    }

    // MARK: - Private

    private func formatUTC(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // RFC 5545 line folding at 75 octets
    private func fold(_ text: String) -> String {
        let lines = text.components(separatedBy: "\r\n")
        return lines.map { line -> String in
            var result = ""
            var count = 0
            var isFirst = true
            for char in line.unicodeScalars {
                let bytes = String(char).utf8.count
                if count + bytes > 75 && !isFirst {
                    result += "\r\n "
                    count = 1
                }
                result += String(char)
                count += bytes
                isFirst = false
            }
            return result
        }.joined(separator: "\r\n")
    }
}
