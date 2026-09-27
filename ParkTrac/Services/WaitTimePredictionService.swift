import Foundation
import SwiftData

struct HourlyAverage: Identifiable {
    var id: Int { hour }
    let hour: Int
    let averageWait: Double
    let isProjected: Bool   // true = future hour (estimated from history/baseline)
}

struct PredictionResult {
    let bestTimeAdvice: String
    let historicalAverage: Int?
    let historicalSampleCount: Int
    let closureAverageDuration: Int?
    let closureSampleCount: Int
    let hourlyAverages: [HourlyAverage]
    let dataSource: PredictionDataSource
    // Closure progress (non-nil only when ride is currently DOWN)
    let closureElapsedMinutes: Int?
    let closureProgressPct: Double?    // elapsed / average; nil if no avg yet
    let closureIsOverdue: Bool         // elapsed > 130% of average
}

enum PredictionDataSource {
    case none
    case communityBaseline
    case personalHistory(Int)   // count of data points
}

struct WaitTimePredictionService {

    // MARK: - General Wisdom

    static func bestTimeAdvice(for group: ParkGroup) -> String {
        switch group {
        case .disney:
            return "Best times: Rope drop (9–10am) or evenings after 7pm"
        case .universal:
            return "Best times: First 2 hours after open or last hour before close"
        case .tokyoDisney:
            return "Best times: Be at the gate well before opening — lines build early — or the last 2 hours"
        case .universalJapan:
            return "Best times: Before opening or the last hour; Super Nintendo World may need an area timed-entry ticket"
        }
    }

    // MARK: - Per-Ride Prediction

    static func predict(
        rideId: String,
        parkGroup: ParkGroup,
        parkName: String = "",
        currentStatus: String? = nil,
        context: ModelContext
    ) -> PredictionResult {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)

        // Fetch wait time records for this ride
        let predicate = #Predicate<WaitTimeRecord> { $0.rideId == rideId }
        let records = (try? context.fetch(FetchDescriptor<WaitTimeRecord>(predicate: predicate))) ?? []

        // Build hourly averages from personal history
        var byHour: [Int: [Int]] = [:]
        for record in records {
            let h = calendar.component(.hour, from: record.recordedAt)
            if let mins = record.waitMinutes {
                byHour[h, default: []].append(mins)
            }
        }

        // Build full-day hourly averages (past hours from history; future hours from community baseline or history)
        let baseline = CommunityBaselineService.shared
        let allHours = Set(byHour.keys).union(Set((7...23).filter {
            baseline.adjustedHourlyAvg(for: parkName, hour: $0) != nil
        }))

        var hourlyAverages: [HourlyAverage] = []
        var dataSource: PredictionDataSource = .none
        var maxPersonalCount = 0

        for hour in allHours.sorted() {
            let isPast = hour <= currentHour
            if let values = byHour[hour], !values.isEmpty {
                let avg = Double(values.reduce(0, +)) / Double(values.count)
                hourlyAverages.append(HourlyAverage(hour: hour, averageWait: avg, isProjected: !isPast))
                maxPersonalCount = max(maxPersonalCount, values.count)
            } else if !isPast, let baselineAvg = baseline.adjustedHourlyAvg(for: parkName, hour: hour) {
                // Only fill future hours from community baseline (past holes stay blank)
                hourlyAverages.append(HourlyAverage(hour: hour, averageWait: baselineAvg, isProjected: true))
            }
        }

        // Determine data source label
        if maxPersonalCount >= 5 {
            dataSource = .personalHistory(maxPersonalCount)
        } else if !hourlyAverages.filter(\.isProjected).isEmpty {
            dataSource = .communityBaseline
        }

        // Historical average for same weekday ± 2 hours
        let sameContext = records.filter { record in
            let h = calendar.component(.hour, from: record.recordedAt)
            let wd = calendar.component(.weekday, from: record.recordedAt)
            return wd == currentWeekday && abs(h - currentHour) <= 2 && record.waitMinutes != nil
        }
        let historicalAverage: Int?
        if sameContext.count >= 5 {
            let sum = sameContext.compactMap(\.waitMinutes).reduce(0, +)
            historicalAverage = sum / sameContext.count
        } else {
            historicalAverage = nil
        }

        // Closure duration averages
        let closurePredicate = #Predicate<DowntimeRecord> { record in
            record.rideId == rideId && record.downEnd != nil
        }
        let closures = (try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: closurePredicate))) ?? []
        let durations = closures.compactMap(\.durationMinutes)
        let closureAverage: Int?
        if durations.count >= 3 {
            closureAverage = durations.reduce(0, +) / durations.count
        } else {
            closureAverage = nil
        }

        // Closure elapsed time — only computed when ride is currently DOWN
        var closureElapsedMinutes: Int? = nil
        var closureProgressPct: Double? = nil
        var closureIsOverdue = false

        if currentStatus == "DOWN" {
            let openPredicate = #Predicate<DowntimeRecord> { record in
                record.rideId == rideId && record.downEnd == nil
            }
            if let open = try? context.fetch(FetchDescriptor<DowntimeRecord>(predicate: openPredicate)),
               let openRecord = open.first {
                let elapsed = Int(Date().timeIntervalSince(openRecord.downStart) / 60)
                closureElapsedMinutes = elapsed
                if let avg = closureAverage, avg > 0 {
                    let pct = Double(elapsed) / Double(avg)
                    closureProgressPct = pct
                    closureIsOverdue = pct > 1.3
                }
            }
        }

        return PredictionResult(
            bestTimeAdvice: bestTimeAdvice(for: parkGroup),
            historicalAverage: historicalAverage,
            historicalSampleCount: sameContext.count,
            closureAverageDuration: closureAverage,
            closureSampleCount: closures.count,
            hourlyAverages: hourlyAverages,
            dataSource: dataSource,
            closureElapsedMinutes: closureElapsedMinutes,
            closureProgressPct: closureProgressPct,
            closureIsOverdue: closureIsOverdue
        )
    }

    // MARK: - Park-Level Comparison

    /// Returns % busier (positive) or lighter (negative) vs expected for this park,
    /// day-of-week, and time. Falls back to community baseline when personal history < 10 pts.
    static func parkComparison(
        parkName: String,
        parkId: String,
        currentAvgWait: Double,
        context: ModelContext
    ) -> Double? {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)

        // Try personal history first (all rides for this park, same weekday ± 2h)
        let predicate = #Predicate<WaitTimeRecord> { $0.parkId == parkId }
        let records = (try? context.fetch(FetchDescriptor<WaitTimeRecord>(predicate: predicate))) ?? []

        let sameContext = records.filter { record in
            let h = calendar.component(.hour, from: record.recordedAt)
            let wd = calendar.component(.weekday, from: record.recordedAt)
            return wd == currentWeekday && abs(h - currentHour) <= 2 && record.waitMinutes != nil
        }

        if sameContext.count >= 10 {
            let sum = sameContext.compactMap(\.waitMinutes).reduce(0, +)
            let historicalAvg = Double(sum) / Double(sameContext.count)
            guard historicalAvg > 0 else { return nil }
            return (currentAvgWait - historicalAvg) / historicalAvg * 100
        }

        // Fall back to community baseline
        let baseline = CommunityBaselineService.shared
        guard let baselineAvg = baseline.adjustedHourlyAvg(for: parkName, hour: currentHour),
              baselineAvg > 0 else { return nil }
        return (currentAvgWait - baselineAvg) / baselineAvg * 100
    }
}

// MARK: - Wait Forecast (ride sheet)

/// The ride sheet's forecast: this ride's expected wait for each open hour today
/// (`RideProfile.waitsByHour` — the same numbers the Smart Planner and Tip Board use)
/// and one plain-language call: go now, or wait for a better hour.
enum WaitForecast {
    struct Bar: Equatable, Identifiable {
        var id: Int { hour }
        let hour: Int
        let wait: Int
    }

    enum Call: Equatable {
        /// Now is within 10 min of the best time left today
        case goNow(wait: Int)
        /// A later hour today saves at least 10 min
        case waitUntil(hour: Int, wait: Int, saves: Int)
    }

    enum Trend: Equatable {
        case rising(hour: Int, wait: Int)
        case falling(hour: Int, wait: Int)
    }

    /// A later hour has to save this much to be worth waiting for
    static let worthWaitingMinutes = 10

    /// Last hour you can still get in line: closing at 10:00 → 9pm, at 10:30 → 10pm.
    static func lastHour(closing: Date?, calendar: Calendar = .current) -> Int? {
        guard let closing else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: closing)
        guard let hour = c.hour else { return nil }
        return (c.minute ?? 0) > 0 ? hour : max(0, hour - 1)
    }

    /// Bars for the open hours (falls back to 9am–9pm when hours are unknown).
    static func bars(profile: [Int: Int], openHour: Int?, lastHour: Int?) -> [Bar] {
        let first = openHour ?? 9
        let last = max(first, lastHour ?? 21)
        return (first...last).compactMap { h in profile[h].map { Bar(hour: h, wait: $0) } }
    }

    static func call(profile: [Int: Int], nowHour: Int, currentWait: Int?, lastHour: Int) -> Call? {
        guard let currentWait else { return nil }
        if let best = TipBoard.best(profile: profile, fromHour: nowHour + 1, untilHour: lastHour),
           currentWait - best.wait >= worthWaitingMinutes {
            return .waitUntil(hour: best.hour, wait: best.wait, saves: currentWait - best.wait)
        }
        return .goNow(wait: currentWait)
    }

    /// Where the wait is heading next hour, when it moves by 10+ minutes.
    static func trend(profile: [Int: Int], nowHour: Int, currentWait: Int?, lastHour: Int) -> Trend? {
        guard let currentWait, nowHour + 1 <= lastHour, let next = profile[nowHour + 1] else { return nil }
        if next - currentWait >= worthWaitingMinutes { return .rising(hour: nowHour + 1, wait: next) }
        if currentWait - next >= worthWaitingMinutes { return .falling(hour: nowHour + 1, wait: next) }
        return nil
    }
}

// MARK: - Real vs posted wait (from Rode It! stopwatch logs)

/// "Posted 60 · you usually wait ~45": how long this party really waits compared with the
/// posted time, from `RideLog`s that have both. This ride's own timed rides first, else every
/// timed ride at the resort.
enum WaitReality {
    struct Timed: Equatable {
        let rideId: String
        let posted: Int
        let actual: Int
    }

    enum Basis: Equatable {
        case thisRide(Int)
        case allRides(Int)
    }

    struct Adjustment: Equatable {
        /// actual ÷ posted
        let ratio: Double
        let basis: Basis

        func actual(posted: Int) -> Int { Int((Double(posted) * ratio).rounded()) }

        /// Only worth a line when it changes the wait by 5+ minutes
        func isWorthShowing(posted: Int) -> Bool { abs(actual(posted: posted) - posted) >= 5 }

        /// "from 4 of your rides on it" / "from your 12 timed rides"
        var sourceText: String {
            switch basis {
            case .thisRide(let n): return "from \(n) of your rides on it"
            case .allRides(let n): return "from your \(n) timed rides"
            }
        }
    }

    static let minThisRide = 2
    static let minAllRides = 5

    static func adjustment(for rideId: String, timed: [Timed]) -> Adjustment? {
        let usable = timed.filter { $0.posted > 0 && $0.actual >= 0 }
        let mine = usable.filter { $0.rideId == rideId }
        if mine.count >= minThisRide, let r = medianRatio(mine) {
            return Adjustment(ratio: r, basis: .thisRide(mine.count))
        }
        if usable.count >= minAllRides, let r = medianRatio(usable) {
            return Adjustment(ratio: r, basis: .allRides(usable.count))
        }
        return nil
    }

    private static func medianRatio(_ rows: [Timed]) -> Double? {
        let ratios = rows.map { Double($0.actual) / Double($0.posted) }.sorted()
        guard !ratios.isEmpty else { return nil }
        let mid = ratios.count / 2
        return ratios.count.isMultiple(of: 2) ? (ratios[mid - 1] + ratios[mid]) / 2 : ratios[mid]
    }
}
