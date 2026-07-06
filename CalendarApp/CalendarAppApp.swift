import SwiftUI
import SwiftData
import BackgroundTasks

@MainActor
@main
struct CalendarAppApp: App {

    let container: ModelContainer
    let syncManager: SyncManager

    init() {
        do {
            container = try ModelContainer(for: CalendarEvent.self, CalendarAccount.self, CalendarCollection.self)
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
        syncManager = SyncManager(modelContext: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await syncManager.syncAll() }
                .onAppear { registerBackgroundSync() }
        }
        .modelContainer(container)
        .environment(syncManager)
    }

    private func registerBackgroundSync() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "eu.chladni.CalendarApp.sync",
            using: nil
        ) { task in
            Task { @MainActor in
                await self.syncManager.syncAll()
                task.setTaskCompleted(success: true)
            }
            self.scheduleBackgroundSync()
        }
        scheduleBackgroundSync()
    }

    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: "eu.chladni.CalendarApp.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
