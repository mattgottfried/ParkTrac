import SwiftUI
import SwiftData

struct BadgesView: View {
    @Query private var allRestaurants: [BucketRestaurant]
    @Query private var allHotels: [HotelStay]
    @State private var selectedBadge: BadgeDefinition?

    private var earned: Int {
        allBadges.filter { $0.isEarned(allRestaurants, allHotels) }.count
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Progress header
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(earned) of \(allBadges.count) Badges Earned")
                            .font(.headline)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.yellow.opacity(0.2))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.yellow)
                                    .frame(width: geo.size.width * (Double(earned) / Double(allBadges.count)), height: 6)
                                    .animation(.spring(duration: 0.5), value: earned)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Badge grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(allBadges) { badge in
                        let isEarned = badge.isEarned(allRestaurants, allHotels)
                        BadgeCardView(badge: badge, isEarned: isEarned)
                            .onTapGesture { selectedBadge = badge }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailView(badge: badge, isEarned: badge.isEarned(allRestaurants, allHotels))
        }
    }
}

// MARK: - Badge Card

private struct BadgeCardView: View {
    let badge: BadgeDefinition
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isEarned ? badge.color.opacity(0.15) : Color(.systemFill))
                    .frame(width: 60, height: 60)
                Image(systemName: badge.systemImage)
                    .font(.system(size: 26))
                    .foregroundStyle(isEarned ? badge.color : .secondary.opacity(0.4))

                if isEarned {
                    Circle()
                        .strokeBorder(badge.color.opacity(0.5), lineWidth: 2)
                        .frame(width: 60, height: 60)
                    // checkmark badge
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .background(badge.color, in: Circle())
                        .offset(x: 20, y: -20)
                }
            }

            VStack(spacing: 3) {
                Text(badge.title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isEarned ? .primary : .secondary)
                if !isEarned {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(isEarned ? badge.color.opacity(0.06) : Color(.systemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isEarned ? badge.color.opacity(0.25) : Color.clear, lineWidth: 1)
        )
        .saturation(isEarned ? 1.0 : 0.3)
    }
}

// MARK: - Badge Detail Sheet

private struct BadgeDetailView: View {
    let badge: BadgeDefinition
    let isEarned: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            ZStack {
                Circle()
                    .fill(isEarned ? badge.color.opacity(0.15) : Color(.systemFill))
                    .frame(width: 100, height: 100)
                Image(systemName: badge.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(isEarned ? badge.color : .secondary.opacity(0.4))
            }
            .saturation(isEarned ? 1.0 : 0.2)

            VStack(spacing: 8) {
                Text(badge.title)
                    .font(.title2.bold())
                Text(badge.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isEarned {
                Label("Earned", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1), in: Capsule())
            } else {
                VStack(spacing: 6) {
                    Text("How to earn")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(badge.howToEarn)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(isEarned ? badge.color : .gray)
        }
        .padding()
        .presentationDetents([.fraction(0.45)])
        .presentationDragIndicator(.hidden)
    }
}
