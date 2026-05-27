import Foundation

// MARK: - Data models for JSON decoding

private struct BaselineFile: Codable {
    let parks: [String: ParkBaseline]
}

private struct ParkBaseline: Codable {
    let hourly: [String: Double]
    let weekday: [String: Double]
}

// MARK: - Service

struct CommunityBaselineService {
    static let shared = CommunityBaselineService()

    private let parks: [String: ParkBaseline]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "CommunityBaselines", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(BaselineFile.self, from: data)
        else {
            parks = [:]
            return
        }
        parks = decoded.parks
    }

    // MARK: - Lookup

    /// Average wait time (minutes) for a park at a given hour of day (24h).
    func hourlyAvg(for parkName: String, hour: Int) -> Double? {
        parks[matchKey(parkName)]?.hourly[String(hour)]
    }

    /// Crowd level percentage (0–100) for a park on a given weekday (1=Sun … 7=Sat).
    func weekdayPct(for parkName: String, weekday: Int) -> Double? {
        parks[matchKey(parkName)]?.weekday[String(weekday)]
    }

    /// Typical wait minutes for a park at a given hour, scaled by today's weekday pattern.
    func adjustedHourlyAvg(for parkName: String, hour: Int) -> Double? {
        guard let base = hourlyAvg(for: parkName, hour: hour) else { return nil }
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        guard let todayPct = weekdayPct(for: parkName, weekday: today) else { return base }

        // Compute average weekday pct to normalise
        guard let allPcts = parks[matchKey(parkName)]?.weekday.values, !allPcts.isEmpty else { return base }
        let avgPct = allPcts.reduce(0, +) / Double(allPcts.count)
        guard avgPct > 0 else { return base }

        return base * (todayPct / avgPct)
    }

    // MARK: - Private

    /// Flexible case-insensitive partial-name match.
    private func matchKey(_ name: String) -> String {
        let lower = name.lowercased()
        // Direct match first
        if parks[lower] != nil { return lower }
        // Partial match (e.g. "Magic Kingdom" hits "magic kingdom")
        if let key = parks.keys.first(where: { lower.contains($0) || $0.contains(lower) }) {
            return key
        }
        return lower
    }
}
