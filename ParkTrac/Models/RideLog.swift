import Foundation
import SwiftData

@Model
final class RideLog {
    var rideId: String = ""
    var rideName: String = ""
    var parkId: String = ""
    var parkName: String = ""
    var resort: String = ""
    var riddenAt: Date = Date()
    var waitMinutes: Int?
    var actualWaitMinutes: Int? = nil
    var notes: String = ""
    /// One photo from the ride, picked when logging it ("Rode It!" only, not the stopwatch quick-log)
    @Attribute(.externalStorage) var photoData: Data? = nil
    /// Whether `GoodTimeToRide` flagged a deal on this ride at the moment it was logged — feeds
    /// the "Deal Hunter" badge. Stamped only where a live deal check is available (the ride
    /// detail sheet's save paths); older logs and the Live Activity "I'm On" path default false.
    var wasGoodTimeDeal: Bool = false
    /// Whether this log landed within 15 min of the park's actual opening — feeds the
    /// "Rope Dropper" badge. Stamped only where a live schedule lookup is available.
    var wasNearRopeDrop: Bool = false

    init(
        rideId: String,
        rideName: String,
        parkId: String,
        parkName: String,
        resort: String,
        riddenAt: Date = .now,
        waitMinutes: Int? = nil,
        actualWaitMinutes: Int? = nil,
        notes: String = "",
        photoData: Data? = nil,
        wasGoodTimeDeal: Bool = false,
        wasNearRopeDrop: Bool = false
    ) {
        self.rideId             = rideId
        self.rideName           = rideName
        self.parkId             = parkId
        self.parkName           = parkName
        self.resort             = resort
        self.riddenAt           = riddenAt
        self.waitMinutes        = waitMinutes
        self.actualWaitMinutes  = actualWaitMinutes
        self.notes              = notes
        self.photoData          = photoData
        self.wasGoodTimeDeal    = wasGoodTimeDeal
        self.wasNearRopeDrop    = wasNearRopeDrop
    }
}

// MARK: - Visit Day helper (computed from RideLog entries)

struct VisitDay: Identifiable {
    let id: Date            // start of day
    let resort: String
    let entries: [RideLog]

    var parks: [String] { Array(Set(entries.map(\.parkName))).sorted() }
    var totalRides: Int  { entries.count }
    var rideNames: [String] { entries.map(\.rideName) }
}

// MARK: - Trip grouping and comparison (pure)
// A "trip" is a run of visit days with no long gap between them — the app has no explicit
// trip boundaries in RideLog, so this infers them from the dates actually logged.

struct VisitTrip: Identifiable {
    let id: Date             // first day's date
    let days: [VisitDay]     // ascending by date

    var lastDay: Date { days.last?.id ?? id }
    var dayCount: Int { days.count }
    var totalRides: Int { days.reduce(0) { $0 + $1.totalRides } }
    var rideNames: Set<String> { Set(days.flatMap(\.rideNames)) }
}

/// This trip's single best day so far — the day with the most rides logged. A simple, honest
/// stat (not weighted by Good Time deals, which aren't persisted per day).
struct TripHighlightDay: Equatable {
    let date: Date
    let rideCount: Int
}

enum TripHighlight {
    static func bestDay(trip: VisitTrip) -> TripHighlightDay? {
        guard let best = trip.days.max(by: { $0.totalRides < $1.totalRides }), best.totalRides > 0 else { return nil }
        return TripHighlightDay(date: best.id, rideCount: best.totalRides)
    }
}

/// This trip's progress against the same point in the previous trip (same day-count into each).
struct TripComparison: Equatable {
    let currentRides: Int
    let priorRidesByThisPoint: Int
    let newRideNames: [String]     // ridden this trip, never on the previous one
    var rideDifference: Int { currentRides - priorRidesByThisPoint }
}

/// Minutes spent standing in line *today*: completed rides (the timed actual wait, else the
/// posted one) plus the currently running wait-timer, if any — a live, running number, unlike
/// `DayRecap.minutesInLine` which is only read after the fact.
enum StandingTime {
    static func minutes(today: [(posted: Int?, actual: Int?)], activeTimerStart: Date? = nil, now: Date = .now) -> Int {
        let completed = today.reduce(0) { $0 + ($1.actual ?? $1.posted ?? 0) }
        let live = activeTimerStart.map { max(0, Int(now.timeIntervalSince($0) / 60)) } ?? 0
        return completed + live
    }
}

/// Whether a log landed within a window of the park's actual opening — feeds `RideLog.wasNearRopeDrop`.
/// The schedule lookup itself happens at the call site (a live `WaitTimesViewModel` is needed);
/// this is just the pure time comparison.
enum RopeDropLogging {
    static func isNearOpen(riddenAt: Date, openTime: Date?, thresholdMinutes: Int = 15) -> Bool {
        guard let openTime else { return false }
        let diff = riddenAt.timeIntervalSince(openTime)
        return diff >= 0 && diff <= Double(thresholdMinutes) * 60
    }
}

/// "New personal best" — today's ride count beats every other single day ever logged (at this
/// resort). Shown live in My Day as you ride, distinct from `StandingTime` (minutes, not count).
enum RideDayRecord {
    static func isNewRecord(todayCount: Int, pastDayCounts: [Int]) -> Bool {
        guard todayCount > 0 else { return false }
        return pastDayCounts.allSatisfy { todayCount > $0 }
    }
}

/// Whether the current (possibly still in progress) trip has already caught up to or passed the
/// *previous* trip's final ride count — worth celebrating before this trip even ends, unlike
/// `TripComparison` above which only compares at the same day-count into each trip.
enum TripRecord {
    static func hasBeatLastTrip(currentRides: Int, previousTripTotalRides: Int) -> Bool {
        previousTripTotalRides > 0 && currentRides > previousTripTotalRides
    }
}

/// A gentle "take a break" nudge after a solid stretch of rides with no real gap between them —
/// pairs with `StandingTime`, which only measures time, not pacing.
enum RestReminder {
    static let rideStreakThreshold = 4
    /// On a hot day, breaks matter more — fewer back-to-back rides before the nudge fires.
    static let hotRideStreakThreshold = 3
    /// A gap under this still counts as "no break"; a gap over it resets the streak.
    static let maxGapMinutes = 20

    /// True once the most recent `rideStreakThreshold` (or more, `hotRideStreakThreshold` on a
    /// hot day) rides today were each logged within `maxGapMinutes` of the one before, and the
    /// last of them was itself recent — so the nudge doesn't surface hours after the fact.
    static func shouldNudge(todaysRideTimes: [Date], now: Date = .now, isHot: Bool = false) -> Bool {
        let threshold = isHot ? hotRideStreakThreshold : rideStreakThreshold
        let sorted = todaysRideTimes.sorted()
        guard sorted.count >= threshold else { return false }
        let recent = sorted.suffix(threshold)
        for (a, b) in zip(recent, recent.dropFirst()) where b.timeIntervalSince(a) > Double(maxGapMinutes) * 60 {
            return false
        }
        guard let last = recent.last else { return false }
        return now.timeIntervalSince(last) <= Double(maxGapMinutes) * 60
    }
}

/// The earliest time a ride was logged — "First ridden: June 2022" on its detail page.
enum FirstRidden {
    static func date(_ logDates: [Date]) -> Date? { logDates.min() }
}

/// Round-number ride-count celebrations — the 100th ride on a favorite coaster, the 500th ride
/// overall at a resort. `crossed` compares before/after counts so only the highest milestone
/// actually reached in that step fires (normally just one, since counts are checked after every
/// single new log).
enum RideMilestone {
    static let thresholds = [10, 25, 50, 100, 200, 500, 1000]

    static func crossed(oldCount: Int, newCount: Int) -> Int? {
        thresholds.last { $0 > oldCount && $0 <= newCount }
    }
}

/// A checklist challenge — every ride in a park, ridden this trip (not lifetime), matched by name
/// against the park's actual roster so a bingo only ever counts rides that exist there.
enum ParkBingo {
    static func progress(roster: [String], riddenThisTrip: Set<String>) -> (ridden: [String], remaining: [String]) {
        let rosterSet = Set(roster)
        let ridden = rosterSet.intersection(riddenThisTrip).sorted()
        let remaining = rosterSet.subtracting(riddenThisTrip).sorted()
        return (ridden, remaining)
    }
}

/// Consecutive years with at least one logged ride, counting back from the most recent year
/// that has history — "5 years running" for a repeat annual visitor.
enum AnnualStreak {
    static func count(years: Set<Int>, through: Int = Calendar.current.component(.year, from: .now)) -> Int {
        guard let start = years.filter({ $0 <= through }).max() else { return 0 }
        var year = start
        var streak = 0
        while years.contains(year) {
            streak += 1
            year -= 1
        }
        return streak
    }
}

/// The ride ridden most across all logs, ties broken by name for stable output (pure).
enum MostRiddenRide {
    static func pick(counts: [String: Int]) -> (name: String, count: Int)? {
        counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }
            .map { (name: $0.key, count: $0.value) }
    }
}

// MARK: - "On this day" memories (pure)

struct OnThisDayMemory {
    let yearsAgo: Int
    let rideCount: Int
    let parks: [String]
    /// A ride ridden more than once that day, if any
    let repeatRide: (name: String, count: Int)?
}

enum OnThisDayMemories {
    /// The most recent earlier year (up to `maxYears` back) with a logged visit on this same
    /// month and day — nil if there's no history yet.
    static func find(logs: [RideLog], resort: String, today: Date = .now, maxYears: Int = 8,
                     calendar: Calendar = .current) -> OnThisDayMemory? {
        let todayComps = calendar.dateComponents([.month, .day], from: today)
        for yearsAgo in 1...maxYears {
            guard let target = calendar.date(byAdding: .year, value: -yearsAgo, to: today) else { continue }
            let targetYear = calendar.component(.year, from: target)
            let dayLogs = logs.filter { log in
                guard log.resort == resort else { return false }
                let c = calendar.dateComponents([.year, .month, .day], from: log.riddenAt)
                return c.year == targetYear && c.month == todayComps.month && c.day == todayComps.day
            }
            guard !dayLogs.isEmpty else { continue }
            let parks = Array(Set(dayLogs.map(\.parkName))).sorted()
            let counts = Dictionary(dayLogs.map { ($0.rideName, 1) }, uniquingKeysWith: +)
            let repeatRide = counts.filter { $0.value > 1 }
                .max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }
                .map { (name: $0.key, count: $0.value) }
            return OnThisDayMemory(yearsAgo: yearsAgo, rideCount: dayLogs.count, parks: parks, repeatRide: repeatRide)
        }
        return nil
    }
}

enum VisitTripGrouper {
    /// Visit days more than `maxGapDays` apart (a rest day or two is still the same trip;
    /// a multi-week gap is a new one) are grouped into one `VisitTrip`. `days` needn't be sorted.
    static func group(_ days: [VisitDay], maxGapDays: Int = 2, calendar: Calendar = .current) -> [VisitTrip] {
        let sorted = days.sorted { $0.id < $1.id }
        var groups: [[VisitDay]] = []
        for day in sorted {
            if let last = groups.last?.last,
               let gap = calendar.dateComponents([.day], from: last.id, to: day.id).day,
               gap <= maxGapDays + 1 {
                groups[groups.count - 1].append(day)
            } else {
                groups.append([day])
            }
        }
        return groups.compactMap { g in g.first.map { VisitTrip(id: $0.id, days: g) } }
    }

    /// The most recent trip vs. the one before it, both counted only through the current trip's
    /// day-count so a 3-day trip so far is compared fairly to the previous trip's first 3 days.
    static func compareLatestToPrevious(_ trips: [VisitTrip]) -> TripComparison? {
        guard trips.count >= 2 else { return nil }
        let current = trips[trips.count - 1]
        let previous = trips[trips.count - 2]
        let priorThroughSamePoint = previous.days.prefix(current.dayCount).reduce(0) { $0 + $1.totalRides }
        let newNames = current.rideNames.subtracting(previous.rideNames)
        return TripComparison(currentRides: current.totalRides, priorRidesByThisPoint: priorThroughSamePoint,
                              newRideNames: newNames.sorted())
    }
}
