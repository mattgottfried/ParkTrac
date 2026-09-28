import Foundation

/// Rain plan: Open-Meteo's hourly rain chance for the resort (the same free API as the Stats
/// weather card). Wet hours push the Smart Planner and Next Up toward indoor rides
/// (`DayPlanBuilder.build(…wetHours:)`), and a heads-up goes out before the rain arrives.
enum RainForecast {
    /// An hour counts as wet at this chance of rain or more
    static let threshold = 50

    struct Window: Equatable {
        /// First wet hour (0–23)
        let start: Int
        /// Hour the rain is expected to stop (exclusive)
        let end: Int
    }

    static func wetHours(_ probabilities: [Int: Int], threshold: Int = threshold) -> Set<Int> {
        Set(probabilities.filter { $0.value >= threshold }.map(\.key))
    }

    /// The next run of wet hours starting at or after `fromHour` (including one already going on).
    static func nextWindow(wetHours: Set<Int>, fromHour: Int) -> Window? {
        guard let start = wetHours.filter({ $0 >= fromHour }).min() else { return nil }
        var end = start + 1
        while wetHours.contains(end) { end += 1 }
        return Window(start: start, end: end)
    }

    /// "Rain likely 3–5 PM" / "Rain likely until 5 PM" / "Rain likely 11 AM–1 PM"
    static func headline(_ window: Window, nowHour: Int) -> String {
        if window.start <= nowHour { return "Rain likely until \(hourText(window.end))" }
        let sameHalf = (window.start < 12) == (window.end < 12 || window.end == 24)
        let start = sameHalf ? hourNumber(window.start) : hourText(window.start)
        return "Rain likely \(start)–\(hourText(window.end))"
    }

    static func hourNumber(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)"
    }

    static func hourText(_ hour: Int) -> String {
        "\(hourNumber(hour)) \(hour % 24 < 12 ? "AM" : "PM")"
    }

    /// Open-Meteo `hourly.time` ("2026-10-10T15:00", resort-local with timezone=auto) +
    /// `hourly.precipitation_probability` → today's hour → chance. `today` is "2026-10-10".
    static func parse(_ data: Data, today: String) -> [Int: Int]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String],
              let chances = hourly["precipitation_probability"] as? [Any] else { return nil }
        var out: [Int: Int] = [:]
        for (i, time) in times.enumerated() where i < chances.count && time.hasPrefix(today) {
            let parts = time.split(separator: "T")
            guard parts.count == 2, let hour = Int(parts[1].prefix(2)) else { continue }
            if let chance = chances[i] as? Int { out[hour] = chance }
            else if let chance = chances[i] as? Double { out[hour] = Int(chance.rounded()) }
        }
        return out
    }
}

@MainActor
@Observable
final class RainForecastService {
    static let shared = RainForecastService()

    static let alertsEnabledKey = "rainAlerts"
    static var alertsEnabled: Bool {
        UserDefaults.standard.object(forKey: alertsEnabledKey) as? Bool ?? true
    }

    private struct Entry {
        let fetchedAt: Date
        let day: String
        let chances: [Int: Int]
    }

    private var entries: [ParkGroup: Entry] = [:]
    private var inFlight: Set<ParkGroup> = []

    private init() {}

    /// Today's wet hours at the resort (empty until loaded, or when it's dry).
    func wetHours(for resort: ParkGroup, now: Date = .now) -> Set<Int> {
        guard let entry = entries[resort], entry.day == Self.dayString(now, resort: resort) else { return [] }
        return RainForecast.wetHours(entry.chances)
    }

    /// The next rain window today from this hour on.
    func window(for resort: ParkGroup, now: Date = .now) -> RainForecast.Window? {
        RainForecast.nextWindow(wetHours: wetHours(for: resort, now: now), fromHour: Self.hour(now, resort: resort))
    }

    func headline(for resort: ParkGroup, now: Date = .now) -> String? {
        window(for: resort, now: now).map { RainForecast.headline($0, nowHour: Self.hour(now, resort: resort)) }
    }

    /// Refetches at most every 30 minutes, then sends the once-a-day heads-up if rain is close.
    func refreshIfNeeded(resort: ParkGroup) async {
        let now = Date.now
        let day = Self.dayString(now, resort: resort)
        let stale = entries[resort].map { $0.day != day || now.timeIntervalSince($0.fetchedAt) > 30 * 60 } ?? true
        if stale, !inFlight.contains(resort) {
            inFlight.insert(resort)
            defer { inFlight.remove(resort) }
            let c = resort.weatherCoordinate
            // Heat heads-up (HeatForecast.swift) rides along on this same request — one extra
            // `hourly` field, not a second fetch — see that type's doc comment.
            let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(c.lat)&longitude=\(c.lon)"
                + "&hourly=precipitation_probability,apparent_temperature&temperature_unit=fahrenheit"
                + "&timezone=auto&forecast_days=1"
            if let url = URL(string: urlString) {
                let result = try? await URLSession.shared.data(from: url)
                if let result {
                    if let chances = RainForecast.parse(result.0, today: day) {
                        entries[resort] = Entry(fetchedAt: now, day: day, chances: chances)
                    }
                    HeatForecastService.shared.ingest(resort: resort, data: result.0, day: day, now: now)
                }
            }
        }
        notifyIfNeeded(resort: resort, now: now)
    }

    /// "Rain likely around 3 PM" — once a day per resort, 15–60 minutes before the first wet hour.
    private func notifyIfNeeded(resort: ParkGroup, now: Date) {
        guard Self.alertsEnabled, let window = window(for: resort, now: now) else { return }
        let hour = Self.hour(now, resort: resort)
        let minute = Self.calendar(for: resort).component(.minute, from: now)
        guard window.start == hour + 1, minute >= 15 else { return }
        let key = "rainNotified_\(resort.rawValue)_\(Self.dayString(now, resort: resort))"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        NotificationService.shared.fireRainHeadsUp(
            resort: resort, headline: RainForecast.headline(window, nowHour: hour))
    }

    // MARK: Resort-local time

    private static func calendar(for resort: ParkGroup) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resort.timeZone
        return cal
    }

    static func hour(_ date: Date, resort: ParkGroup) -> Int {
        calendar(for: resort).component(.hour, from: date)
    }

    static func dayString(_ date: Date, resort: ParkGroup) -> String {
        let c = calendar(for: resort).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
