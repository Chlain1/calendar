import SwiftData
import Foundation

@Model
final class CalendarAccount {
    var id: UUID
    var name: String
    var serverURL: String
    var username: String
    var principalURL: String?
    var calendarHomeSetURL: String?
    var isEnabled: Bool
    var isEventKitAccount: Bool

    @Relationship(deleteRule: .cascade)
    var collections: [CalendarCollection]

    init(name: String, serverURL: String, username: String) {
        self.id = UUID()
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.isEnabled = true
        self.isEventKitAccount = false
        self.collections = []
    }
}

extension CalendarAccount: Identifiable {}
