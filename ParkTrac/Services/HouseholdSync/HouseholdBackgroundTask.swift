import Foundation
import BackgroundTasks

/// Background-task fallback for household sync, mirroring `BackgroundRefreshService`'s
/// structure. Silent push (registered in `HouseholdSyncService`) is the primary near-real-time
/// path; this covers the case where push doesn't arrive (killed app, no network at push time).
struct HouseholdBackgroundTask {

    static let taskIdentifier = "com.parktrac.household.sync"

    @MainActor
    static func schedule() {
        // Only worth scheduling for users who've actually joined a household.
        guard HouseholdSyncService.shared.currentCode != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(task: BGAppRefreshTask) {
        schedule()

        let workTask = Task {
            await HouseholdSyncService.shared.runFullSync()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
