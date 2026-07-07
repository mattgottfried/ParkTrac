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
            // Fetch both resorts for 24/7 data coverage regardless of which is active
            await fetchAndRecord(resort: .disney, container: container)
            await fetchAndRecord(resort: .universal, container: container)
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
        guard let parks = try? await ParkAPIService.shared.fetchDestinationChildren(destinationId: resort.destinationId) else { return }

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
    }
}
