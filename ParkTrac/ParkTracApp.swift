import SwiftUI
import SwiftData
import BackgroundTasks
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct ParkTracApp: App {
    let container: ModelContainer = PersistenceController.container

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshService.taskIdentifier,
            using: nil
        ) { task in
            BackgroundRefreshService.run(task: task as! BGAppRefreshTask)
        }
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start { _ in
            StoreService.shared.markAdsReady()
        }
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    NSUbiquitousKeyValueStore.default.synchronize()
                    await BucketListService.shared.seedIfNeeded(context: container.mainContext)
                    try? DiningSeedService.seedIfNeeded(context: container.mainContext)
                    BackgroundRefreshService.schedule()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Re-queue the background task every time the app comes to the foreground
            // so iOS always has a fresh request to schedule against
            if phase == .active { BackgroundRefreshService.schedule() }
        }
    }
}
