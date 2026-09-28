import Foundation
import SwiftData
import UserNotifications

// MARK: - Rule (pure, unit tested)

/// "Slinky Dog Dash is 35 min — usually ~70 at this time." Compares a ride's posted wait with
/// what this phone has recorded for it (`WaitTimeRecord`, one sample per ride per 10 min) at the
/// same hour on earlier days, else the server's community history, else earlier today.
enum GoodTimeToRide {
    enum Basis: Equatable {
        /// Median of earlier days' waits within an hour of now
        case usualAtThisTime
        /// The server's community history for this ride at this hour on this weekday
        case typicalForDay
        /// Median of today's earlier waits
        case earlierToday
    }

    struct Usual: Equatable {
        let minutes: Int
        let basis: Basis
    }

    struct Deal: Equatable {
        let rideId: String
        let wait: Int
        let usual: Usual

        var savedMinutes: Int { usual.minutes - wait }

        /// "usually ~70" / "was ~70 earlier"
        var shortText: String {
            usual.basis == .earlierToday ? "was ~\(usual.minutes) earlier" : "usually ~\(usual.minutes)"
        }

        /// "usually ~70 min at this time" / "down from ~70 min earlier today"
        var longText: String {
            usual.basis == .earlierToday
                ? "down from ~\(usual.minutes) min earlier today"
                : "usually ~\(usual.minutes) min at this time"
        }
    }

    /// Enough history to trust: samples on at least this many earlier days…
    static let minHistoryDays = 2
    /// …and at least this many samples in total
    static let minSamples = 6
    /// Ignore the last few samples today so the current dip doesn't lower its own baseline
    static let todayExclusionWindow: TimeInterval = 30 * 60
    /// A deal needs a meaningful usual wait…
    static let minUsual = 20
    /// …the wait at most this fraction of it…
    static let maxFraction = 0.65
    /// …and at least this many minutes saved
    static let minSaved = 15

    /// - Parameter community: the server's typical wait for this ride at this hour
    ///   (`CommunityHistoryService`), used when this phone has no history of its own at this time.
    static func usual(samples: [(date: Date, wait: Int)], community: Int? = nil, now: Date = .now,
                      calendar: Calendar = .current) -> Usual? {
        let hour = calendar.component(.hour, from: now)
        let today = calendar.startOfDay(for: now)

        // Earlier days, same time of day (±1 h)
        let history = samples.filter { s in
            s.date < today && abs(calendar.component(.hour, from: s.date) - hour) <= 1
        }
        let days = Set(history.map { calendar.startOfDay(for: $0.date) })
        if days.count >= minHistoryDays, history.count >= minSamples, let m = median(history.map(\.wait)) {
            return Usual(minutes: m, basis: .usualAtThisTime)
        }

        // Everyone's history (server), this weekday at this hour
        if let community {
            return Usual(minutes: community, basis: .typicalForDay)
        }

        // Today, before the last half hour
        let earlier = samples.filter { $0.date >= today && $0.date < now.addingTimeInterval(-todayExclusionWindow) }
        if earlier.count >= minSamples, let m = median(earlier.map(\.wait)) {
            return Usual(minutes: m, basis: .earlierToday)
        }
        return nil
    }

    static func deal(rideId: String, wait: Int?, isOperating: Bool, usual: Usual?) -> Deal? {
        guard isOperating, let wait, let usual, usual.minutes >= minUsual else { return nil }
        guard Double(wait) <= Double(usual.minutes) * maxFraction, usual.minutes - wait >= minSaved else { return nil }
        return Deal(rideId: rideId, wait: wait, usual: usual)
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

// MARK: - Service

/// Current deals for the rides on screen, refreshed after every live-data update, plus a
/// once-a-day nudge per Must-Do ride.
@Observable
final class GoodTimeService {
    static let shared = GoodTimeService()

    static let alertsEnabledKey = "goodTimeAlerts"
    static var alertsEnabled: Bool {
        UserDefaults.standard.object(forKey: alertsEnabledKey) as? Bool ?? true
    }

    /// Deals keyed by ride id
    private(set) var deals: [String: GoodTimeToRide.Deal] = [:]
    /// Every operating ride's "usual" wait, not just ones that qualify as a deal — for the
    /// "+15 vs usual" delta shown on ride cards.
    private(set) var usuals: [String: GoodTimeToRide.Usual] = [:]

    private init() {}

    func deal(for rideId: String) -> GoodTimeToRide.Deal? { deals[rideId] }
    func usual(for rideId: String) -> GoodTimeToRide.Usual? { usuals[rideId] }

    /// Recompute from recorded history. `mustDo` rides also get a notification (once per ride per day).
    @MainActor
    func update(rides: [DisplayRide], mustDo: Set<String>, context: ModelContext, notify: Bool = true) {
        let operating = rides.filter { $0.isOperating && $0.waitMinutes != nil }
        guard !operating.isEmpty else {
            deals = [:]
            usuals = [:]
            return
        }
        // 14 days is plenty for "usual at this time" and keeps the fetch small
        let since = Date.now.addingTimeInterval(-14 * 86_400)
        let ids = Set(operating.map(\.id))
        let descriptor = FetchDescriptor<WaitTimeRecord>(predicate: #Predicate { $0.recordedAt >= since })
        let records = ((try? context.fetch(descriptor)) ?? []).filter { ids.contains($0.rideId) }
        var byRide: [String: [(date: Date, wait: Int)]] = [:]
        for r in records {
            guard let wait = r.waitMinutes, r.status == "OPERATING" || r.status.isEmpty else { continue }
            byRide[r.rideId, default: []].append((date: r.recordedAt, wait: wait))
        }

        var next: [String: GoodTimeToRide.Deal] = [:]
        var nextUsuals: [String: GoodTimeToRide.Usual] = [:]
        let hour = Calendar.current.component(.hour, from: .now)
        for ride in operating {
            let community = CommunityHistoryService.shared.waitsByHour(rideId: ride.id, parkId: ride.parkId)[hour]
            guard let usual = GoodTimeToRide.usual(samples: byRide[ride.id] ?? [], community: community) else { continue }
            nextUsuals[ride.id] = usual
            if let deal = GoodTimeToRide.deal(rideId: ride.id, wait: ride.waitMinutes,
                                              isOperating: ride.isOperating, usual: usual) {
                next[ride.id] = deal
            }
        }
        deals = next
        usuals = nextUsuals

        guard notify, Self.alertsEnabled else { return }
        for ride in operating where mustDo.contains(ride.id) {
            guard let deal = next[ride.id], !Self.alreadyNotifiedToday(rideId: ride.id) else { continue }
            Self.markNotified(rideId: ride.id)
            NotificationService.shared.fireGoodTimeToRide(rideId: ride.id, rideName: ride.name, deal: deal)
        }
    }

    /// Must-Do deals first (biggest saving first), then others — for the Wait Times strip.
    func ranked(rides: [DisplayRide], mustDo: Set<String>, limit: Int = 5) -> [(ride: DisplayRide, deal: GoodTimeToRide.Deal)] {
        rides.compactMap { ride -> (ride: DisplayRide, deal: GoodTimeToRide.Deal)? in
            guard let deal = deals[ride.id] else { return nil }
            return (ride: ride, deal: deal)
        }
            .sorted {
                let a = mustDo.contains($0.ride.id), b = mustDo.contains($1.ride.id)
                if a != b { return a }
                return $0.deal.savedMinutes > $1.deal.savedMinutes
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Once a day per ride

    private static func notifiedKey(_ rideId: String) -> String { "goodTimeNotified_\(rideId)" }

    private static func alreadyNotifiedToday(rideId: String) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: notifiedKey(rideId)) as? Date else { return false }
        return Calendar.current.isDateInToday(last)
    }

    private static func markNotified(rideId: String) {
        UserDefaults.standard.set(Date.now, forKey: notifiedKey(rideId))
    }
}

// MARK: - Easy Wins (pure)
// Shortest absolute waits right now, regardless of Must-Do status or whether it's a "deal"
// (a ride can have a short line without ever having a long "usual" to compare against) — quick
// things to knock out while waiting for a Must-Do to get shorter, or filling a gap in the day.

enum EasyWins {
    static let maxWaitMinutes = 15

    static func pick(rides: [DisplayRide], excluding: Set<String> = [], limit: Int = 6) -> [DisplayRide] {
        rides
            .filter { ride in
                guard ride.isOperating, let wait = ride.waitMinutes, !excluding.contains(ride.id) else { return false }
                return wait <= maxWaitMinutes
            }
            .sorted { ($0.waitMinutes ?? Int.max) < ($1.waitMinutes ?? Int.max) }
            .prefix(limit)
            .map { $0 }
    }
}
