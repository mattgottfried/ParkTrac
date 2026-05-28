import SwiftUI
import SwiftData

struct BucketRestaurantListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BucketRestaurant.name) private var allRestaurants: [BucketRestaurant]
    @State private var searchText: String = ""
    @State private var selectedRestaurant: BucketRestaurant?

    private var resortRestaurants: [BucketRestaurant] {
        allRestaurants.filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var filtered: [BucketRestaurant] {
        resortRestaurants
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: resortRestaurants.filter(\.isVisited).count,
                total: resortRestaurants.count,
                label: "Restaurants Visited",
                color: .orange
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            statsStrip
                .padding(.bottom, 8)

            Group {
                if !searchText.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { restaurant in
                            BucketRestaurantRow(restaurant: restaurant)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRestaurant = restaurant }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search restaurants")
        }
        .sheet(item: $selectedRestaurant) { BucketRestaurantDetailView(restaurant: $0) }
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        let resort = appState.selectedResort.rawValue
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statCard(
                    label: "Table Service",
                    visited: allRestaurants.filter { $0.resort == resort && $0.category == "Table Service" && $0.isVisited }.count,
                    total: allRestaurants.filter { $0.resort == resort && $0.category == "Table Service" }.count,
                    color: .green
                )
                statCard(
                    label: "Quick Service",
                    visited: allRestaurants.filter { $0.resort == resort && $0.category == "Quick Service" && $0.isVisited }.count,
                    total: allRestaurants.filter { $0.resort == resort && $0.category == "Quick Service" }.count,
                    color: .orange
                )
                statCard(
                    label: "Character Dining",
                    visited: allRestaurants.filter { $0.resort == resort && $0.category == "Character Dining" && $0.isVisited }.count,
                    total: allRestaurants.filter { $0.resort == resort && $0.category == "Character Dining" }.count,
                    color: .blue
                )
            }
            .padding(.horizontal)
        }
    }

    private func statCard(label: String, visited: Int, total: Int, color: Color) -> some View {
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

private struct BucketRestaurantRow: View {
    let restaurant: BucketRestaurant

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: restaurant.isVisited ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(restaurant.isVisited ? Color.green : Color.secondary)
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
        case "Character Dining": return .blue
        case "Table Service":    return .green
        default:                 return .gray
        }
    }
}
