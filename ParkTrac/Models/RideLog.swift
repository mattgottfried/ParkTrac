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
        photoData: Data? = nil
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

/// This trip's progress against the same point in the previous trip (same day-count into each).
struct TripComparison: Equatable {
    let currentRides: Int
    let priorRidesByThisPoint: Int
    let newRideNames: [String]     // ridden this trip, never on the previous one
    var rideDifference: Int { currentRides - priorRidesByThisPoint }
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
