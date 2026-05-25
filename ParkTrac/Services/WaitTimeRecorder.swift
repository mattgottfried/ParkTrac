import Foundation
import SwiftData

@MainActor
final class WaitTimeRecorder {
    static let shared = WaitTimeRecorder()

    private var lastStatuses: [String: String] = [:]  // rideId → last known status

    func record(rides: [DisplayRide], parkId: String, context: ModelContext) {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now)!

        for ride in rides {
            // Insert wait time record
            let record = WaitTimeRecord(
                rideId: ride.id,
                rideName: ride.name,
                parkId: parkId,
                recordedAt: now,
                waitMinutes: ride.waitMinutes,
                status: ride.status ?? "UNKNOWN"
            )
            context.insert(record)

            // Track DOWN transitions
            let previousStatus = lastStatuses[ride.id]
            let currentStatus = ride.status ?? "UNKNOWN"

            if currentStatus == "DOWN" && previousStatus != "DOWN" {
                // Ride just went DOWN — open a new downtime record
                let downtime = DowntimeRecord(
                    rideId: ride.id,
                    rideName: ride.name,
                    parkId: parkId,
                    downStart: now
                )
                context.insert(downtime)
            } else if currentStatus == "OPERATING" && previousStatus == "DOWN" {
                // Ride came back up — close the open downtime record
                closeOpenDowntime(for: ride.id, at: now, context: context)
            }

            lastStatuses[ride.id] = currentStatus
        }

        // Prune records older than 90 days
        pruneOldRecords(before: cutoff, context: context)

        try? context.save()
    }

    private func closeOpenDowntime(for rideId: String, at date: Date, context: ModelContext) {
        let predicate = #Predicate<DowntimeRecord> { record in
            record.rideId == rideId && record.downEnd == nil
        }
        let open = (try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: predicate))) ?? []
        for record in open {
            record.downEnd = date
        }
    }

    private func pruneOldRecords(before cutoff: Date, context: ModelContext) {
        let predicate = #Predicate<WaitTimeRecord> { $0.recordedAt < cutoff }
        let old = (try? context.fetch(FetchDescriptor<WaitTimeRecord>(predicate: predicate))) ?? []
        for record in old { context.delete(record) }
    }

    func minutesDown(for rideId: String, context: ModelContext) -> Int? {
        let predicate = #Predicate<DowntimeRecord> { record in
            record.rideId == rideId && record.downEnd == nil
        }
        guard let open = try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: predicate)),
              let record = open.first else { return nil }
        return Int(Date().timeIntervalSince(record.downStart) / 60)
    }
}
