import SwiftUI
import SwiftData
import Foundation

@Model
final class CalendarCollection {
    var id: UUID
    var href: String
    var displayName: String
    var ctag: String?
    var colorHex: String?
    var isEnabled: Bool
    var accountID: UUID

    init(href: String, displayName: String, accountID: UUID, colorHex: String? = nil) {
        self.id = UUID()
        self.href = href
        self.displayName = displayName
        self.colorHex = colorHex
        self.isEnabled = true
        self.accountID = accountID
    }

    var color: Color { Color(hex: colorHex ?? "#4A90D9") ?? .blue }
}

extension CalendarCollection: Identifiable {}
