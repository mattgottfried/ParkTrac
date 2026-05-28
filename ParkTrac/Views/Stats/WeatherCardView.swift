import SwiftUI

struct WeatherCardView: View {
    let resort: ParkGroup

    @State private var weather: WeatherSnapshot?
    @State private var isLoading = false

    private var coordinate: (lat: Double, lon: Double) {
        switch resort {
        case .disney:    return (28.3772, -81.5707)
        case .universal: return (28.4793, -81.4643)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weather", systemImage: "cloud.sun.fill")
                .font(.headline).foregroundStyle(.blue)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let w = weather {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("\(Int(w.currentTemp))°F")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text(w.conditionLabel)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 50)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "thermometer.high").foregroundStyle(.red)
                            Text("High: \(Int(w.high))°F").font(.caption)
                        }
                        HStack {
                            Image(systemName: "thermometer.low").foregroundStyle(.blue)
                            Text("Low: \(Int(w.low))°F").font(.caption)
                        }
                        HStack {
                            Image(systemName: "drop.fill").foregroundStyle(.blue)
                            Text("Rain: \(w.rainChance)%").font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Weather unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task { await loadWeather() }
        .onChange(of: resort) { _, _ in Task { await loadWeather() } }
    }

    @MainActor
    private func loadWeather() async {
        isLoading = true
        let (lat, lon) = coordinate
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weathercode,precipitation_probability&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=auto&forecast_days=1"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            isLoading = false; return
        }
        if let current = json["current"] as? [String: Any],
           let daily = json["daily"] as? [String: Any] {
            let temp = current["temperature_2m"] as? Double ?? 0
            let code = current["weathercode"] as? Int ?? 0
            let rain = current["precipitation_probability"] as? Int ?? 0
            let highs = daily["temperature_2m_max"] as? [Double] ?? []
            let lows  = daily["temperature_2m_min"] as? [Double] ?? []
            weather = WeatherSnapshot(currentTemp: temp, high: highs.first ?? 0, low: lows.first ?? 0,
                                      rainChance: rain, weatherCode: code)
        }
        isLoading = false
    }
}

struct WeatherSnapshot {
    let currentTemp: Double
    let high: Double
    let low: Double
    let rainChance: Int
    let weatherCode: Int

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
