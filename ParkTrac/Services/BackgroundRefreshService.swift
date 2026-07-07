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

    private static func fetchAndRecord(resort: ParkGroup, container: ModelContainer) async {
        guard let parks = try? await ParkAPIService.shared.fetchDestinationChildren(destinationId: resort.destinationId) else { return }

        let context = ModelContext(container)
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now)!

        await withTaskGroup(of: Void.self) { group in
            for park in parks {
                group.addTask {
                    guard let entries = try? await ParkAPIService.shared.fetchLiveData(for: park.id) else { return }
                    let rides = entries.map { DisplayRide(live: $0, parkId: park.id, location: nil) }
                    await processRides(rides, parkId: park.id, at: now, context: context)
                }
            }
        }

        // Prune wait time snapshots older than 90 days
        let predicate = #Predicate<WaitTimeRecord> { $0.recordedAt < cutoff }
        let old = (try? context.fetch(FetchDescriptor<WaitTimeRecord>(predicate: predicate))) ?? []
        for record in old { context.delete(record) }

        // Prune completed downtime records older than 90 days
        let dtPredicate = #Predicate<DowntimeRecord> { r in
            r.downEnd != nil && r.downEnd! < cutoff
        }
        let oldDowntime = (try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: dtPredicate))) ?? []
        for record in oldDowntime { context.delete(record) }

        try? context.save()
    }

    @MainActor
    private static func processRides(_ rides: [DisplayRide], parkId: String, at now: Date, context: ModelContext) {
        for ride in rides {
            guard ride.isOperating || ride.status == "DOWN" else { continue }

            // Record wait time snapshot
            context.insert(WaitTimeRecord(
                rideId: ride.id,
                rideName: ride.name,
                parkId: parkId,
                recordedAt: now,
                waitMinutes: ride.waitMinutes,
                status: ride.status ?? "UNKNOWN"
            ))

            // DOWN-transition tracking using UserDefaults as persistent last-status store
            let key = "lastStatus_\(ride.id)"
            let prevStatus = UserDefaults.standard.string(forKey: key)
            let currStatus = ride.status ?? "UNKNOWN"

            if currStatus == "DOWN" && prevStatus != "DOWN" {
                // Ride just went down — open a new DowntimeRecord
                context.insert(DowntimeRecord(
                    rideId: ride.id,
                    rideName: ride.name,
                    parkId: parkId,
                    downStart: now
                ))
            } else if currStatus == "OPERATING" && prevStatus == "DOWN" {
                // Ride came back up — close any open DowntimeRecord
                closeOpenDowntimes(for: ride.id, at: now, context: context)
            }

            UserDefaults.standard.set(currStatus, forKey: key)
        }
    }

    private static func closeOpenDowntimes(for rideId: String, at date: Date, context: ModelContext) {
        let predicate = #Predicate<DowntimeRecord> { record in
            record.rideId == rideId && record.downEnd == nil
        }
        let open = (try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: predicate))) ?? []
        for record in open {
            record.downEnd = date
        }
    }
}
