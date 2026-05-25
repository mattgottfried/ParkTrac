import Foundation
import SwiftData

struct HourlyAverage: Identifiable {
    var id: Int { hour }
    let hour: Int
    let averageWait: Double
}

struct PredictionResult {
    let bestTimeAdvice: String
    let historicalAverage: Int?
    let historicalSampleCount: Int
    let closureAverageDuration: Int?
    let closureSampleCount: Int
    let hourlyAverages: [HourlyAverage]
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

    static func generalPeakHours(for group: ParkGroup) -> [Int] {
        switch group {
        case .disney:    return [11, 12, 13, 14, 15]
        case .universal: return [12, 13, 14, 15, 16]
        }
    }

    // MARK: - Personal History

    static func predict(
        rideId: String,
        parkGroup: ParkGroup,
        context: ModelContext
    ) -> PredictionResult {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)

        // Fetch wait time records for this ride
        let predicate = #Predicate<WaitTimeRecord> { $0.rideId == rideId }
        let records = (try? context.fetch(FetchDescriptor<WaitTimeRecord>(predicate: predicate))) ?? []

        // Hourly averages across all time
        var byHour: [Int: [Int]] = [:]
        for record in records {
            let h = calendar.component(.hour, from: record.recordedAt)
            if let mins = record.waitMinutes {
                byHour[h, default: []].append(mins)
            }
        }
        let hourlyAverages: [HourlyAverage] = byHour.compactMap { hour, values in
            guard !values.isEmpty else { return nil }
            return HourlyAverage(hour: hour, averageWait: Double(values.reduce(0, +)) / Double(values.count))
        }.sorted { $0.hour < $1.hour }

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

        return PredictionResult(
            bestTimeAdvice: bestTimeAdvice(for: parkGroup),
            historicalAverage: historicalAverage,
            historicalSampleCount: sameContext.count,
            closureAverageDuration: closureAverage,
            closureSampleCount: closures.count,
            hourlyAverages: hourlyAverages
        )
    }
}
