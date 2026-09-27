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
        for parkId in parkIds where cache[parkId]?.day != today.day && !inFlight.contains(parkId) {
            guard let url = ThrillTrackServer.url("v1/history", query: [
                URLQueryItem(name: "parkId", value: parkId),
                URLQueryItem(name: "weekday", value: String(today.weekday)),
            ]) else { continue }
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

// MARK: - Crowd calendar from real waits

/// Each park's average posted wait per day (10 AM–6 PM), from the server's history
/// (`GET /v1/days?resort=<apiSlug>`).
struct CrowdDays: Codable, Equatable {
    struct Park: Codable, Equatable {
        let id: String
        let name: String
        /// "2026-10-10" → average wait in minutes
        let days: [String: Double]
    }

    let slug: String
    let parks: [Park]
}

/// How a calendar day's crowd level was worked out (pure, unit tested).
enum CrowdHistory {
    enum Source: Equatable {
        /// Recorded that day: the resort-wide average wait
        case measured(avg: Double)
        /// Upcoming: the same weekday over the last few weeks
        case recent(avg: Double, days: Int)
        /// No data: the seasonal pattern (`CrowdCalendarService`)
        case seasonal
    }

    /// Predictions from recent weeks only reach this far ahead; after that, seasonal
    static let predictionDays = 14
    static let lookbackWeeks = 4

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Resort-wide average on a day: the mean of the parks recorded that day.
    static func average(on key: String, in data: CrowdDays) -> Double? {
        let values = data.parks.compactMap { $0.days[key] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func source(for date: Date, today: Date = .now, data: CrowdDays?,
                       calendar: Calendar = .current) -> Source {
        guard let data else { return .seasonal }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: today)
        if day <= start, let avg = average(on: dayKey(day, calendar: calendar), in: data) {
            return .measured(avg: avg)
        }
        guard day >= start,
              let ahead = calendar.dateComponents([.day], from: start, to: day).day,
              ahead <= predictionDays else { return .seasonal }
        // Same weekday, 1…4 weeks before the day (and not in the future)
        let past = (1...lookbackWeeks).compactMap { week -> Double? in
            guard let d = calendar.date(byAdding: .day, value: -7 * week, to: day), d < start else { return nil }
            return average(on: dayKey(d, calendar: calendar), in: data)
        }
        guard past.count >= 2 else { return .seasonal }
        return .recent(avg: past.reduce(0, +) / Double(past.count), days: past.count)
    }

    static func level(for date: Date, resort: ParkGroup, data: CrowdDays?, today: Date = .now,
                      calendar: Calendar = .current) -> CrowdLevel {
        switch source(for: date, today: today, data: data, calendar: calendar) {
        case .measured(let avg), .recent(let avg, _): return CrowdLevel.from(averageWait: avg)
        case .seasonal: return CrowdCalendarService.crowdLevel(for: date, resort: resort)
        }
    }

    /// "Magic Kingdom 45 · EPCOT 30" for a recorded day
    static func parkLine(on date: Date, data: CrowdDays, calendar: Calendar = .current) -> String? {
        let key = dayKey(date, calendar: calendar)
        let parts = data.parks.compactMap { park in park.days[key].map { "\(park.name) \(Int($0.rounded()))" } }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class CrowdHistoryService {
    static let shared = CrowdHistoryService()

    private static let defaultsKey = "crowdDays"
    private static let maxAge: TimeInterval = 6 * 3600

    private struct Cached: Codable {
        let fetchedAt: Date
        let data: CrowdDays
    }

    private var cache: [String: Cached] = [:]
    private var inFlight: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Cached].self, from: data) {
            cache = saved
        }
    }

    func days(for resort: ParkGroup) -> CrowdDays? { cache[resort.apiSlug]?.data }

    func refreshIfNeeded(resort: ParkGroup) async {
        let slug = resort.apiSlug
        if let cached = cache[slug], Date.now.timeIntervalSince(cached.fetchedAt) < Self.maxAge { return }
        guard !inFlight.contains(slug),
              let url = ThrillTrackServer.url("v1/days", query: [URLQueryItem(name: "resort", value: slug)]) else { return }
        inFlight.insert(slug)
        defer { inFlight.remove(slug) }
        let result = try? await URLSession.shared.data(from: url)
        guard let result, (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CrowdDays.self, from: result.0) else { return }
        cache[slug] = Cached(fetchedAt: .now, data: decoded)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// The ThrillTrack server (alerts + history): the Instant Alerts server URL from Settings.
enum ThrillTrackServer {
    @MainActor
    static func url(_ path: String, query: [URLQueryItem]) -> URL? {
        let base = InstantAlertsService.shared.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (base.isEmpty ? InstantAlertsService.defaultServerURL : base)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: root + "/" + path)
        components?.queryItems = query
        return components?.url
    }
}
