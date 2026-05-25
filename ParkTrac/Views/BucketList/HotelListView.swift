import SwiftUI
import SwiftData

struct HotelListView: View {
    @Query(sort: \HotelStay.hotelName) private var allHotels: [HotelStay]
    @State private var selectedResort: String = "All"
    @State private var selectedHotel: HotelStay?

    private var resorts: [String] { ["All", "Walt Disney World", "Universal Orlando"] }

    private var filtered: [HotelStay] {
        selectedResort == "All" ? allHotels : allHotels.filter { $0.resort == selectedResort }
    }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: allHotels.filter(\.isVisited).count,
                total: allHotels.count,
                label: "Hotels Stayed",
                color: .purple
            )
            .padding()

            Picker("Resort", selection: $selectedResort) {
                ForEach(resorts, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                ForEach(filtered) { hotel in
                    HotelRow(hotel: hotel)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedHotel = hotel }
                }
            }
            .listStyle(.plain)
        }
        .sheet(item: $selectedHotel) { HotelDetailView(hotel: $0) }
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
