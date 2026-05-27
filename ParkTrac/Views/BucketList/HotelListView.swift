import SwiftUI
import SwiftData

struct HotelListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \HotelStay.hotelName) private var allHotels: [HotelStay]
    @State private var selectedHotel: HotelStay?

    private var resortHotels: [HotelStay] {
        allHotels.filter { $0.resort == appState.selectedResort.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: resortHotels.filter(\.isVisited).count,
                total: resortHotels.count,
                label: "Hotels Stayed",
                color: .purple
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            hotelStatsStrip
                .padding(.bottom, 8)

            List {
                ForEach(resortHotels) { hotel in
                    HotelRow(hotel: hotel)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedHotel = hotel }
                }
            }
            .listStyle(.plain)
        }
        .sheet(item: $selectedHotel) { HotelDetailView(hotel: $0) }
    }

    // MARK: - Stats strip

    private var hotelStatsStrip: some View {
        let resort = appState.selectedResort.rawValue
        let isDisney = appState.selectedResort == .disney
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if isDisney {
                    hotelStatCard(label: "Deluxe / DVC",
                        visited: allHotels.filter { $0.resort == resort && ($0.tier == "Deluxe" || $0.tier == "Disney Vacation Club") && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && ($0.tier == "Deluxe" || $0.tier == "Disney Vacation Club") }.count,
                        color: .purple)
                    hotelStatCard(label: "Moderate",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Moderate" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Moderate" }.count,
                        color: .orange)
                    hotelStatCard(label: "Value",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Value" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Value" }.count,
                        color: .green)
                } else {
                    hotelStatCard(label: "Premier",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Premier" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Premier" }.count,
                        color: .purple)
                    hotelStatCard(label: "Preferred",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Preferred" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Preferred" }.count,
                        color: .orange)
                    hotelStatCard(label: "Standard",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Standard" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Standard" }.count,
                        color: .green)
                }
            }
            .padding(.horizontal)
        }
    }

    private func hotelStatCard(label: String, visited: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Int((Double(visited) / Double(total) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(visited) / \(total)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text("\(pct)%")
                .font(.caption2)
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HotelRow: View {
    let hotel: HotelStay

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hotel.isVisited ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(hotel.isVisited ? .purple : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(hotel.hotelName)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(hotel.isVisited, color: .secondary)
                HStack(spacing: 6) {
                    Text(hotel.resort)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(hotel.tier)
                        .font(.caption)
                        .foregroundStyle(tierColor(hotel.tier))
                }
                if hotel.isVisited, let checkIn = hotel.checkIn, let nights = hotel.nightsStayed {
                    Text("\(checkIn, style: .date) · \(nights) night\(nights == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if hotel.isVisited, let avg = hotel.averageRating {
                StarDisplayView(rating: avg)
            }
        }
        .padding(.vertical, 4)
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "Deluxe", "Premier":    return .purple
        case "Disney Vacation Club": return .blue
        case "Preferred":            return .green
        case "Moderate", "Standard": return .orange
        default:                     return .gray
        }
    }
}
