import Foundation

struct WeatherSnapshot {
    let currentTemp: Double
    let high: Double
    let low: Double
    let rainChance: Int
    let weatherCode: Int
    /// True when any of the next 3 hours has a >=50% precipitation chance.
    let rainLikelySoon: Bool

    var conditionLabel: String {
        switch weatherCode {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly Cloudy"
        case 45, 48: return "Foggy"
        case 51...67: return "Drizzle/Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 95...99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }
}

enum WeatherService {
    private static let hourlyTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    static func fetch(latitude: Double, longitude: Double) async -> WeatherSnapshot? {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weathercode,precipitation_probability&hourly=precipitation_probability&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=auto&forecast_days=1"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let daily = json["daily"] as? [String: Any] else {
            return nil
        }

        let temp = current["temperature_2m"] as? Double ?? 0
        let code = current["weathercode"] as? Int ?? 0
        let rain = current["precipitation_probability"] as? Int ?? 0
        let highs = daily["temperature_2m_max"] as? [Double] ?? []
        let lows = daily["temperature_2m_min"] as? [Double] ?? []

        return WeatherSnapshot(
            currentTemp: temp,
            high: highs.first ?? 0,
            low: lows.first ?? 0,
            rainChance: rain,
            weatherCode: code,
            rainLikelySoon: rainLikelySoon(from: json)
        )
    }

    private static func rainLikelySoon(from json: [String: Any]) -> Bool {
        guard let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String],
              let probs = hourly["precipitation_probability"] as? [Int] else {
            return false
        }
        let now = Date()
        let cutoff = now.addingTimeInterval(3 * 3600)
        for (index, timeString) in times.enumerated() {
            guard index < probs.count,
                  let date = hourlyTimeFormatter.date(from: timeString),
                  date >= now, date <= cutoff else { continue }
            if probs[index] >= 50 { return true }
        }
        return false
    }
}
