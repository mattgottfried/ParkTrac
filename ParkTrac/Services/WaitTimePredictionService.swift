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
