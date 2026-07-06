import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WeekView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(0)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(1)
        }
    }
}
