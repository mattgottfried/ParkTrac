import Foundation
import SwiftData

/// Records wait-time snapshots and DOWN transitions into the telemetry store.
/// Called after every foreground refresh (ParkMapView) and from each background
/// refresh run — the single implementation for both paths.
@MainActor
final class WaitTimeRecorder {
    static let shared = WaitTimeRecorder()

    /// Minimum gap between persisted snapshots per ride. Foreground refreshes
    /// arrive every 60s; predictions only need ~10-minute resolution.
    private static let snapshotInterval: TimeInterval = 10 * 60
    /// Minimum gap between prune passes (each pass fetches all expired rows).
    private static let pruneInterval: TimeInterval = 6 * 60 * 60

    private var lastSnapshotAt: [String: Date] = [:]  // rideId → last persisted snapshot

    func record(rides: [DisplayRide], context: ModelContext) {
        let now = Date()

        for ride in rides {
            // Match background behavior: only operating/DOWN rides are meaningful
            guard ride.isOperating || ride.status == "DOWN" else { continue }

            // Snapshots are throttled; transition tracking below never is
            if lastSnapshotAt[ride.id].map({ now.timeIntervalSince($0) >= Self.snapshotInterval }) ?? true {
                lastSnapshotAt[ride.id] = now
                context.insert(WaitTimeRecord(
                    rideId: ride.id,
                    rideName: ride.name,
                    parkId: ride.parkId,
                    recordedAt: now,
                    waitMinutes: ride.waitMinutes,
                    status: ride.status ?? "UNKNOWN"
                ))
            }

            // DOWN-transition tracking. Last status lives in UserDefaults (shared
            // with background refresh runs) so alternating foreground/background
            // passes never double-open or fail to close a DowntimeRecord.
            let key = "lastStatus_\(ride.id)"
            let previousStatus = UserDefaults.standard.string(forKey: key)
            let currentStatus = ride.status ?? "UNKNOWN"

            if currentStatus == "DOWN" && previousStatus != "DOWN" {
                context.insert(DowntimeRecord(
                    rideId: ride.id,
                    rideName: ride.name,
                    parkId: ride.parkId,
                    downStart: now
                ))
            } else if currentStatus == "OPERATING" && previousStatus == "DOWN" {
                closeOpenDowntime(for: ride.id, at: now, context: context)
            }

            UserDefaults.standard.set(currentStatus, forKey: key)
        }

        pruneIfDue(now: now, context: context)

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

    // MARK: - Pruning

    private func pruneIfDue(now: Date, context: ModelContext) {
        let lastPrune = UserDefaults.standard.object(forKey: "lastTelemetryPruneAt") as? Date
        guard lastPrune.map({ now.timeIntervalSince($0) >= Self.pruneInterval }) ?? true else { return }
        UserDefaults.standard.set(now, forKey: "lastTelemetryPruneAt")

        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now.addingTimeInterval(-90 * 86400)

        // Wait time snapshots older than 90 days
        let predicate = #Predicate<WaitTimeRecord> { $0.recordedAt < cutoff }
        let old = (try? context.fetch(FetchDescriptor<WaitTimeRecord>(predicate: predicate))) ?? []
        for record in old { context.delete(record) }

        // Completed downtime records older than 90 days
        let dtPredicate = #Predicate<DowntimeRecord> { r in
            r.downEnd != nil && r.downEnd! < cutoff
        }
        let oldDowntime = (try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: dtPredicate))) ?? []
        for record in oldDowntime { context.delete(record) }

        // Orphaned open downtimes: the "came back up" transition was missed
        // (e.g. app closed before the ride reopened). After 24h they only
        // skew closure-duration averages — drop them.
        let orphanCutoff = now.addingTimeInterval(-24 * 60 * 60)
        let orphanPredicate = #Predicate<DowntimeRecord> { r in
            r.downEnd == nil && r.downStart < orphanCutoff
        }
        let orphans = (try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: orphanPredicate))) ?? []
        for record in orphans { context.delete(record) }
    }
}
