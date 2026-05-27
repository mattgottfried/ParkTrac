import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ParkTracApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            BucketRestaurant.self,
            HotelStay.self,
            Restaurant.self,
            WaitTimeRecord.self,
            DowntimeRecord.self,
            RideLog.self,
            DiningReservation.self,
        ])
        return try! ModelContainer(for: schema)
    }()

    init() {
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
                    await BucketListService.shared.seedIfNeeded(context: container.mainContext)
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
