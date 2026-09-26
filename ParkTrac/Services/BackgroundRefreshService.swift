import Foundation
import BackgroundTasks
import SwiftData

// MARK: - Background Refresh Service

struct BackgroundRefreshService {

    static let taskIdentifier = "com.parktrac.background.refresh"

    // MARK: - Scheduling

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour minimum
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Task Handler

    @MainActor
    static func run(task: BGAppRefreshTask) {
        // Reschedule immediately so the next run is always queued
        schedule()

        let container = try? PersistenceController.makeTelemetryContainer()
        guard let container else {
            task.setTaskCompleted(success: false)
            return
        }

        let workTask = Task {
            // Fetch every resort for 24/7 data coverage regardless of which is active
            for resort in ParkGroup.allCases {
                await fetchAndRecord(resort: resort, container: container)
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Core fetch + record

    @MainActor
    private static func fetchAndRecord(resort: ParkGroup, container: ModelContainer) async {
        guard let parks = try? await ParkAPIService.shared.fetchParks(for: resort) else { return }

        var allRides: [DisplayRide] = []
        await withTaskGroup(of: [DisplayRide].self) { group in
            for park in parks {
                group.addTask {
                    guard let entries = try? await ParkAPIService.shared.fetchLiveData(for: park.id) else { return [] }
                    return entries
                        .filter { $0.entityType == "ATTRACTION" }
                        .map { DisplayRide(live: $0, parkId: park.id, location: nil) }
                }
            }
            for await rides in group {
                allRides.append(contentsOf: rides)
            }
        }

        // Snapshot + DOWN tracking + pruning all live in WaitTimeRecorder —
        // the same implementation the foreground refresh uses
        let context = ModelContext(container)
        WaitTimeRecorder.shared.record(rides: allRides, context: context)
        // Must-Do "good time to ride" nudges in the background too (≈hourly)
        let mustDo = Set((NSUbiquitousKeyValueStore.default.array(forKey: "wishList") as? [String])
                         ?? UserDefaults.standard.stringArray(forKey: "wishList") ?? [])
        GoodTimeService.shared.update(rides: allRides, mustDo: mustDo, context: context)
        // Lightning Lane watches get background coverage too (≈hourly, iOS decides)
        LightningLaneWatchService.shared.check(rides: allRides)
        ReopenWatchService.shared.check(rides: allRides)
        // Keeps the alert server's copy from expiring
        InstantAlertsService.shared.refreshIfStale()
    }
}
