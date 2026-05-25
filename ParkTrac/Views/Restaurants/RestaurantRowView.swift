import SwiftUI

struct RestaurantRowView: View {
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(restaurant.name)
                    .font(.headline)
                Spacer()
                StarDisplayView(rating: restaurant.averageRating)
            }

            HStack {
                Label(restaurant.park, systemImage: "mappin.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(restaurant.dateVisited, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Matt:").font(.caption2).foregroundStyle(.secondary)
                    StarDisplayView(rating: Double(restaurant.mattRating))
                }
                HStack(spacing: 4) {
                    Text("Wife:").font(.caption2).foregroundStyle(.secondary)
                    StarDisplayView(rating: Double(restaurant.wifeRating))
                }
            }

            if !restaurant.notes.isEmpty {
                Text(restaurant.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
