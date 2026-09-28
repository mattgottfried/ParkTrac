import Foundation

/// Heat heads-up: Florida (and Japan summer) afternoons can run brutally hot. Uses the same
/// Open-Meteo hourly forecast `RainForecastService` already fetches (one extra `hourly` param —
/// `apparent_temperature`, the "feels like" figure — piggybacks on that request rather than a
/// second network round trip), so the two features share one fetch/cache cycle per resort.
/// Hot hours push the Smart Planner and Next Up toward indoor/shaded rides the same way wet
/// hours do (`DayPlanBuilder.build(…wetHours:)` — a hot hour counts as "wet" for that purpose,
/// since the fix is the same: get inside), and a once-a-day heads-up goes out before it peaks.
enum HeatForecast {
    /// °F feels-like at or above this counts as a hot hour
    static let thresholdF = 95.0

    struct Window: Equatable {
        /// First hot hour (0–23)
        let start: Int
        /// Hour it's expected to cool back down below the threshold (exclusive)
        let end: Int
    }

    static func hotHours(_ feelsLikeF: [Int: Double], threshold: Double = thresholdF) -> Set<Int> {
        Set(feelsLikeF.filter { $0.value >= threshold }.map(\.key))
    }

    /// The next run of hot hours starting at or after `fromHour` (including one already going on).
    static func nextWindow(hotHours: Set<Int>, fromHour: Int) -> Window? {
        guard let start = hotHours.filter({ $0 >= fromHour }).min() else { return nil }
        var end = start + 1
        while hotHours.contains(end) { end += 1 }
        return Window(start: start, end: end)
    }

    /// "Heat likely 1–4 PM" / "Heat likely until 4 PM"
    static func headline(_ window: Window, nowHour: Int) -> String {
        if window.start <= nowHour { return "Heat likely until \(RainForecast.hourText(window.end))" }
        let sameHalf = (window.start < 12) == (window.end < 12 || window.end == 24)
        let start = sameHalf ? RainForecast.hourNumber(window.start) : RainForecast.hourText(window.start)
        return "Heat likely \(start)–\(RainForecast.hourText(window.end))"
    }

    /// Open-Meteo `hourly.time` + `hourly.apparent_temperature` (°F when `temperature_unit=fahrenheit`)
    /// → today's hour → feels-like. `today` is "2026-10-10".
    static func parse(_ data: Data, today: String) -> [Int: Double]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String],
              let temps = hourly["apparent_temperature"] as? [Any] else { return nil }
        var out: [Int: Double] = [:]
        for (i, time) in times.enumerated() where i < temps.count && time.hasPrefix(today) {
            let parts = time.split(separator: "T")
            guard parts.count == 2, let hour = Int(parts[1].prefix(2)) else { continue }
            if let t = temps[i] as? Double { out[hour] = t }
            else if let t = temps[i] as? Int { out[hour] = Double(t) }
        }
        return out
    }
}

@MainActor
@Observable
final class HeatForecastService {
    static let shared = HeatForecastService()

    static let alertsEnabledKey = "heatAlerts"
    static var alertsEnabled: Bool {
        UserDefaults.standard.object(forKey: alertsEnabledKey) as? Bool ?? true
    }

    private struct Entry {
        let fetchedAt: Date
        let day: String
        let feelsLikeF: [Int: Double]
    }

    private var entries: [ParkGroup: Entry] = [:]

    private init() {}

    /// Today's hot hours at the resort (empty until loaded, or when it isn't hot).
    func hotHours(for resort: ParkGroup, now: Date = .now) -> Set<Int> {
        guard let entry = entries[resort], entry.day == RainForecastService.dayString(now, resort: resort) else { return [] }
        return HeatForecast.hotHours(entry.feelsLikeF)
    }

    /// The next heat window today from this hour on.
    func window(for resort: ParkGroup, now: Date = .now) -> HeatForecast.Window? {
        HeatForecast.nextWindow(hotHours: hotHours(for: resort, now: now),
                                fromHour: RainForecastService.hour(now, resort: resort))
    }

    func headline(for resort: ParkGroup, now: Date = .now) -> String? {
        window(for: resort, now: now).map { HeatForecast.headline($0, nowHour: RainForecastService.hour(now, resort: resort)) }
    }

    /// Called with the same response `RainForecastService.refreshIfNeeded` just fetched, so this
    /// never makes its own network request — see the type-level doc for why.
    func ingest(resort: ParkGroup, data: Data, day: String, now: Date = .now) {
        guard let feelsLikeF = HeatForecast.parse(data, today: day) else { return }
        entries[resort] = Entry(fetchedAt: now, day: day, feelsLikeF: feelsLikeF)
        notifyIfNeeded(resort: resort, now: now)
    }

    /// "Heat likely around 1 PM — plan an indoor break" — once a day per resort, 15–60 minutes
    /// before the first hot hour.
    private func notifyIfNeeded(resort: ParkGroup, now: Date) {
        guard Self.alertsEnabled, let window = window(for: resort, now: now) else { return }
        let hour = RainForecastService.hour(now, resort: resort)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resort.timeZone
        let minute = cal.component(.minute, from: now)
        guard window.start == hour + 1, minute >= 15 else { return }
        let key = "heatNotified_\(resort.rawValue)_\(RainForecastService.dayString(now, resort: resort))"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        NotificationService.shared.fireHeatHeadsUp(
            resort: resort, headline: HeatForecast.headline(window, nowHour: hour))
    }
}
