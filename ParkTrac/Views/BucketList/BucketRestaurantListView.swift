import SwiftUI
import SwiftData

struct BucketRestaurantListView: View {
    @Query(sort: \BucketRestaurant.name) private var allRestaurants: [BucketRestaurant]
    @State private var selectedPark: String = "All"
    @State private var selectedRestaurant: BucketRestaurant?

    private var parks: [String] {
        let unique = Set(allRestaurants.map(\.park))
        return ["All"] + unique.sorted()
    }

    private var filtered: [BucketRestaurant] {
        selectedPark == "All" ? allRestaurants : allRestaurants.filter { $0.park == selectedPark }
    }

    private var visited: Int { filtered.filter(\.isVisited).count }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: allRestaurants.filter(\.isVisited).count,
                total: allRestaurants.count,
                label: "Restaurants Visited",
                color: .orange
            )
            .padding()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parks, id: \.self) { park in
                        Button(park == "All" ? "All Parks" : park) {
                            selectedPark = park
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedPark == park ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedPark == park ? Color.orange : Color(.systemGray5))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)

            List {
                ForEach(filtered) { restaurant in
                    BucketRestaurantRow(restaurant: restaurant)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRestaurant = restaurant }
                }
            }
            .listStyle(.plain)
        }
        .sheet(item: $selectedRestaurant) { BucketRestaurantDetailView(restaurant: $0) }
    }
}

private struct BucketRestaurantRow: View {
    let restaurant: BucketRestaurant

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: restaurant.isVisited ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(restaurant.isVisited ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(restaurant.isVisited, color: .secondary)
                HStack(spacing: 6) {
                    Text(restaurant.park)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(restaurant.category)
                        .font(.caption)
                        .foregroundStyle(categoryColor(restaurant.category))
                }
                if restaurant.isVisited, let date = restaurant.visitDate {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if restaurant.isVisited, let avg = restaurant.averageRating {
                StarDisplayView(rating: avg)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Signature Dining": return .purple
        case "Character Dining": return .blue
        case "Table Service":    return .green
        case "Dinner Show":      return .orange
        default:                 return .gray
        }
    }
}
