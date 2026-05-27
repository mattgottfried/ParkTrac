import SwiftUI
import SwiftData

struct MyDiningView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BucketRestaurant.name) private var all: [BucketRestaurant]
    @State private var selectedRestaurant: BucketRestaurant?

    private var resortVisited: [BucketRestaurant] {
        all
            .filter { $0.isVisited && $0.resort == appState.selectedResort.rawValue }
            .sorted { ($0.averageRating ?? 0) > ($1.averageRating ?? 0) }
    }

    private var resortTotal: Int {
        all.filter { $0.resort == appState.selectedResort.rawValue }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BucketProgressView(
                    visited: resortVisited.count,
                    total: resortTotal,
                    label: "Restaurants Visited",
                    color: .orange
                )
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 12)

                if resortVisited.isEmpty {
                    ContentUnavailableView(
                        "Nothing visited yet",
                        systemImage: "fork.knife",
                        description: Text("Mark restaurants as visited in the Bucket List tab.")
                    )
                } else {
                    List {
                        ForEach(resortVisited) { restaurant in
                            DiningRow(restaurant: restaurant)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRestaurant = restaurant }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Dining")
            .sheet(item: $selectedRestaurant) { BucketRestaurantDetailView(restaurant: $0) }
        }
    }
}

private struct DiningRow: View {
    let restaurant: BucketRestaurant

    var body: some View {
        HStack(spacing: 12) {
            // Rating circle
            if let avg = restaurant.averageRating {
                ZStack {
                    Circle()
                        .fill(ratingColor(avg).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(String(format: "%.1f", avg))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ratingColor(avg))
                }
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(.subheadline.weight(.medium))
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
                if let avg = restaurant.averageRating {
                    StarDisplayView(rating: avg)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func ratingColor(_ r: Double) -> Color {
        if r >= 4.5 { return .green }
        if r >= 3.0 { return .orange }
        return .red
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Character Dining": return .blue
        case "Table Service":    return .green
        default:                 return .gray
        }
    }
}
