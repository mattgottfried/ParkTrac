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
        weather = await WeatherService.fetch(latitude: lat, longitude: lon)
        isLoading = false
    }
}
