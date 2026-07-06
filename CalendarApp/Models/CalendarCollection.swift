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
    var eventKitIdentifier: String?
    var allowsModification: Bool

    init(href: String, displayName: String, accountID: UUID, colorHex: String? = nil) {
        self.id = UUID()
        self.href = href
        self.displayName = displayName
        self.colorHex = colorHex
        self.isEnabled = true
        self.accountID = accountID
        self.allowsModification = true
    }

    var color: Color { Color(hex: colorHex ?? "#4A90D9") ?? .blue }
    var isFromEventKit: Bool { eventKitIdentifier != nil }
}

extension CalendarCollection: Identifiable {}
