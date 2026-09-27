import Foundation

/// Typical waits by hour from the ThrillTrack server's community history (`server/history.ts`):
/// every ride at the four resorts is recorded every 10 minutes, all day, whether or not anyone
/// has the app open. `RideProfile.waitsByHour` uses it for hours this phone has no history of
/// its own, so the Wait Forecast, Smart Planner and Tip Board get real per-ride curves.
struct CommunityHistorySummary: Codable, Equatable {
    let parkId: String
    /// 1 = Sunday … 7 = Saturday
    let weekday: Int
    /// Different days the server has recorded for this park
    let days: Int
    /// ride id → local hour ("9") → typical posted wait in minutes
    let rides: [String: [String: Int]]

    func waitsByHour(rideId: String) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for (hour, wait) in rides[rideId] ?? [:] {
            if let h = Int(hour), (0...23).contains(h) { out[h] = wait }
        }
        return out
    }
}

@MainActor
@Observable
final class CommunityHistoryService {
    static let shared = CommunityHistoryService()

    private struct Cached: Codable {
        /// Park-local day the summary is for ("2026-10-10")
        let day: String
        /// The resort's time zone — "today" is checked there, not in the phone's zone
        let timeZoneId: String
        let summary: CommunityHistorySummary
    }

    private static let defaultsKey = "communityHistory"
    private var cache: [String: Cached] = [:]
    private var inFlight: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Cached].self, from: data) {
            cache = saved
        }
    }

    /// Today's typical waits for a ride (empty until the day's summary has loaded).
    func waitsByHour(rideId: String, parkId: String, now: Date = .now) -> [Int: Int] {
        guard let cached = cache[parkId],
              let zone = TimeZone(identifier: cached.timeZoneId),
              cached.day == Self.dayKey(now, timeZone: zone).day else { return [:] }
        return cached.summary.waitsByHour(rideId: rideId)
    }

    /// Days of history behind today's numbers for a park (0 when none).
    func days(parkId: String) -> Int { cache[parkId]?.summary.days ?? 0 }

    /// Fetches each park's summary once per park-local day.
    func refreshIfNeeded(parkIds: [String], timeZone: TimeZone) async {
        let today = Self.dayKey(.now, timeZone: timeZone)
        let base = InstantAlertsService.shared.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        for parkId in parkIds where cache[parkId]?.day != today.day && !inFlight.contains(parkId) {
            var components = URLComponents(string: (base.isEmpty ? InstantAlertsService.defaultServerURL : base)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/history")
            components?.queryItems = [URLQueryItem(name: "parkId", value: parkId),
                                      URLQueryItem(name: "weekday", value: String(today.weekday))]
            guard let url = components?.url else { continue }
            inFlight.insert(parkId)
            defer { inFlight.remove(parkId) }
            let result = try? await URLSession.shared.data(from: url)
            guard let result, (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let summary = Self.decode(result.0) else { continue }
            cache[parkId] = Cached(day: today.day, timeZoneId: timeZone.identifier, summary: summary)
        }
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: Pure (unit tested)

    static func decode(_ data: Data) -> CommunityHistorySummary? {
        try? JSONDecoder().decode(CommunityHistorySummary.self, from: data)
    }

    /// Park-local day string and weekday (1 = Sunday) for `date`.
    static func dayKey(_ date: Date, timeZone: TimeZone) -> (day: String, weekday: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        return (day: String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0), weekday: c.weekday ?? 1)
    }
}
