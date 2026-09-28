import Foundation

/// Past weather for a logged visit day — Open-Meteo's free historical archive (no key), the
/// same provider `RainForecastService` already uses for the forecast. Shown in Visit History
/// for context on why a day was quiet or crowded ("it was raining", "89°F and clear").
struct HistoricalWeatherDay: Codable, Equatable {
    let weatherCode: Int
    let highF: Double
    let precipitationInches: Double
}

enum HistoricalWeather {
    static func parse(_ data: Data, dateKey: String) -> HistoricalWeatherDay? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = json["daily"] as? [String: Any],
              let dates = daily["time"] as? [String],
              let idx = dates.firstIndex(of: dateKey),
              let codes = daily["weathercode"] as? [Any], idx < codes.count,
              let highs = daily["temperature_2m_max"] as? [Any], idx < highs.count,
              let code = intValue(codes[idx]), let high = doubleValue(highs[idx]) else { return nil }
        let precip: Double = {
            guard let precs = daily["precipitation_sum"] as? [Any], idx < precs.count else { return 0 }
            return doubleValue(precs[idx]) ?? 0
        }()
        return HistoricalWeatherDay(weatherCode: code, highF: high, precipitationInches: precip)
    }

    private static func intValue(_ any: Any) -> Int? {
        (any as? Int) ?? (any as? Double).map { Int($0.rounded()) }
    }
    private static func doubleValue(_ any: Any) -> Double? {
        (any as? Double) ?? (any as? Int).map(Double.init)
    }

    /// WMO weather code → a short label and SF Symbol, covering the common daily codes.
    static func describe(_ code: Int) -> (text: String, icon: String) {
        switch code {
        case 0: return ("Clear", "sun.max.fill")
        case 1, 2: return ("Partly Cloudy", "cloud.sun.fill")
        case 3: return ("Cloudy", "cloud.fill")
        case 45, 48: return ("Foggy", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow.fill")
        case 80, 81, 82: return ("Showers", "cloud.heavyrain.fill")
        case 95, 96, 99: return ("Thunderstorms", "cloud.bolt.rain.fill")
        default: return ("Weather", "cloud.fill")
        }
    }
}

@MainActor
@Observable
final class HistoricalWeatherService {
    static let shared = HistoricalWeatherService()

    private static let defaultsKey = "historicalWeatherDays"
    /// The archive lags behind today by about this many days — no point requesting anything newer.
    private static let archiveLagDays = 5

    private var cache: [String: HistoricalWeatherDay] = [:]
    private var inFlight: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: HistoricalWeatherDay].self, from: data) {
            cache = saved
        }
    }

    func day(for date: Date, resort: ParkGroup) -> HistoricalWeatherDay? {
        cache[Self.key(date, resort: resort)]
    }

    func fetchIfNeeded(for date: Date, resort: ParkGroup) async {
        let key = Self.key(date, resort: resort)
        guard cache[key] == nil, !inFlight.contains(key) else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.archiveLagDays, to: .now),
              date < cutoff else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let c = resort.weatherCoordinate
        let dateStr = WaitTimesViewModel.dayString(date, in: resort.timeZone)
        let urlString = "https://archive-api.open-meteo.com/v1/archive?latitude=\(c.lat)&longitude=\(c.lon)"
            + "&start_date=\(dateStr)&end_date=\(dateStr)&daily=weathercode,temperature_2m_max,precipitation_sum"
            + "&temperature_unit=fahrenheit&timezone=auto"
        guard let url = URL(string: urlString) else { return }
        let result = try? await URLSession.shared.data(from: url)
        guard let result, (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let day = HistoricalWeather.parse(result.0, dateKey: dateStr) else { return }
        cache[key] = day
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func key(_ date: Date, resort: ParkGroup) -> String {
        "\(resort.rawValue)|\(WaitTimesViewModel.dayString(date, in: resort.timeZone))"
    }
}
