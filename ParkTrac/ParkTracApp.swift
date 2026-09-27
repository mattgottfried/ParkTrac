import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

@main
struct ParkTracApp: App {
    let container: ModelContainer = PersistenceController.container
    /// Receives the push token for instant alerts
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Must be set before launch finishes so a tap that launched the app is delivered
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationDelegate.registerCategories()
        // Live Activity buttons (Done / Skip / I'm On / Used It) run here
        LiveActivityActionHandler.register()
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshService.taskIdentifier,
            using: nil
        ) { task in
            BackgroundRefreshService.run(task: task as! BGAppRefreshTask)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    NSUbiquitousKeyValueStore.default.synchronize()
                    await BucketListService.shared.seedIfNeeded(context: container.mainContext)
                    BackgroundRefreshService.schedule()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Re-queue the background task every time the app comes to the foreground
            // so iOS always has a fresh request to schedule against
            if phase == .active {
                BackgroundRefreshService.schedule()
                InstantAlertsService.shared.appBecameActive()
                // Refresh the dining countdown for the soonest reservation later
                // today — covers reservations created outside a view (e.g. the
                // email-scraping AppIntent) and clears stale/past activities.
                LiveActivityManager.syncDiningActivity(context: container.mainContext)
            }
        }
    }
}
