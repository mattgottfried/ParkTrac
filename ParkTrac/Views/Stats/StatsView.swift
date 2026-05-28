import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BucketRestaurant.name) private var allRestaurants: [BucketRestaurant]
    @Query(sort: \HotelStay.hotelName)   private var allHotels: [HotelStay]
    @Query(sort: \RideLog.riddenAt, order: .reverse) private var allRideLogs: [RideLog]

    private var resort: String { appState.selectedResort.rawValue }

    // MARK: - Restaurant Stats

    private var resortRestaurants: [BucketRestaurant] { allRestaurants.filter { $0.resort == resort } }
    private var visitedRestaurants: [BucketRestaurant] { resortRestaurants.filter(\.isVisited) }

    private var avgMattRestaurant: Double? {
        let rated = visitedRestaurants.filter { $0.mattRating > 0 }
        guard !rated.isEmpty else { return nil }
        return rated.map(\.mattRating).reduce(0, +) / Double(rated.count)
    }
    private var avgHeatRestaurant: Double? {
        let rated = visitedRestaurants.filter { $0.wifeRating > 0 }
        guard !rated.isEmpty else { return nil }
        return rated.map(\.wifeRating).reduce(0, +) / Double(rated.count)
    }
    private var topRestaurant: BucketRestaurant? {
        visitedRestaurants.filter { ($0.averageRating ?? 0) > 0 }
            .max { ($0.averageRating ?? 0) < ($1.averageRating ?? 0) }
    }

    // MARK: - Hotel Stats

    private var resortHotels: [HotelStay] { allHotels.filter { $0.resort == resort } }
    private var visitedHotels: [HotelStay] { resortHotels.filter(\.isVisited) }

    private var totalNights: Int { visitedHotels.compactMap(\.nightsStayed).reduce(0, +) }
    private var avgMattHotel: Double? {
        let rated = visitedHotels.filter { $0.mattRating > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.map(\.mattRating).reduce(0, +)) / Double(rated.count)
    }
    private var avgHeatHotel: Double? {
        let rated = visitedHotels.filter { $0.wifeRating > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.map(\.wifeRating).reduce(0, +)) / Double(rated.count)
    }
    private var topHotel: HotelStay? {
        visitedHotels.filter { ($0.averageRating ?? 0) > 0 }
            .max { ($0.averageRating ?? 0) < ($1.averageRating ?? 0) }
    }

    // MARK: - Ride Stats

    private var resortRideLogs: [RideLog] { allRideLogs.filter { $0.resort == resort } }

    private var rideLogsThisYear: [RideLog] {
        let startOfYear = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: .now))!
        return resortRideLogs.filter { $0.riddenAt >= startOfYear }
    }

    private var visitDays: [VisitDay] {
        let cal = Calendar.current
        var byDay: [Date: [RideLog]] = [:]
        for log in resortRideLogs {
            let day = cal.startOfDay(for: log.riddenAt)
            byDay[day, default: []].append(log)
        }
        return byDay.map { VisitDay(id: $0.key, resort: resort, entries: $0.value) }
            .sorted { $0.id > $1.id }
    }

    private var topRides: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for log in resortRideLogs { counts[log.rideName, default: 0] += 1 }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Badges

    private var earnedBadges: [BadgeDefinition] {
        allBadges.filter { $0.isEarned(allRestaurants, allHotels, allRideLogs) }
    }
    private var nextBadges: [BadgeDefinition] {
        allBadges.filter { !$0.isEarned(allRestaurants, allHotels, allRideLogs) }.prefix(4).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Restaurants card
                    statsCard(title: "Restaurants", systemImage: "fork.knife", color: .orange) {
                        BucketProgressView(
                            visited: visitedRestaurants.count,
                            total: resortRestaurants.count,
                            label: "Visited",
                            color: .orange
                        )
                        .padding(.horizontal, -4)
                        categoryRow(restaurants: resortRestaurants)
                        Divider()
                        if avgMattRestaurant != nil || avgHeatRestaurant != nil {
                            ratingsRow(matt: avgMattRestaurant, heat: avgHeatRestaurant)
                            Divider()
                        }
                        if let top = topRestaurant {
                            topItemRow(label: "Top Rated", name: top.name, rating: top.averageRating)
                        }
                    }

                    // Hotels card
                    statsCard(title: "Hotels", systemImage: "bed.double.fill", color: .purple) {
                        BucketProgressView(
                            visited: visitedHotels.count,
                            total: resortHotels.count,
                            label: "Stayed",
                            color: .purple
                        )
                        .padding(.horizontal, -4)
                        if totalNights > 0 {
                            HStack {
                                Label("\(totalNights) total nights", systemImage: "moon.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            Divider()
                        }
                        if avgMattHotel != nil || avgHeatHotel != nil {
                            ratingsRow(matt: avgMattHotel, heat: avgHeatHotel)
                            Divider()
                        }
                        if let top = topHotel {
                            topItemRow(label: "Top Rated", name: top.hotelName, rating: top.averageRating)
                        }
                    }

                    // Rides card
                    if !resortRideLogs.isEmpty {
                        statsCard(title: "Rides", systemImage: "figure.jumprope", color: .teal) {
                            HStack(spacing: 16) {
                                rideStatChip(value: "\(resortRideLogs.count)", label: "All Time", color: .teal)
                                rideStatChip(value: "\(rideLogsThisYear.count)", label: "This Year", color: .blue)
                                rideStatChip(value: "\(visitDays.count)", label: "Visits", color: .green)
                            }

                            if !topRides.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Most Ridden")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(topRides, id: \.name) { ride in
                                        HStack {
                                            Text(ride.name).font(.caption).lineLimit(1)
                                            Spacer()
                                            Text("×\(ride.count)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.teal)
                                        }
                                    }
                                }
                            }

                            Divider()
                            HStack {
                                NavigationLink("Ride Counter") { RideCounterView() }
                                    .font(.caption.weight(.medium))
                                Text("·").foregroundStyle(.secondary)
                                NavigationLink("Visit History") { VisitHistoryView() }
                                    .font(.caption.weight(.medium))
                                Spacer()
                            }
                            .foregroundStyle(.teal)
                        }
                    }

                    // Weather card
                    WeatherCardView(resort: appState.selectedResort)

                    // Spending card
                    spendingCard

                    // Crowd Calendar card
                    CrowdCalendarCard(resort: appState.selectedResort)

                    // Badges teaser
                    badgesTeaser
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sub-views

    private func statsCard<Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            content()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func categoryRow(restaurants: [BucketRestaurant]) -> some View {
        let categories: [(String, Color)] = [
            ("Character Dining", .purple),
            ("Table Service", .green),
            ("Quick Service", .orange),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.0) { name, color in
                    let total   = restaurants.filter { $0.category == name }.count
                    let visited = restaurants.filter { $0.category == name && $0.isVisited }.count
                    if total > 0 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(visited) / \(total)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func ratingsRow(matt: Double?, heat: Double?) -> some View {
        HStack(spacing: 16) {
            if let m = matt { ratingChip(label: "Matt", rating: m) }
            if let h = heat { ratingChip(label: "Heather", rating: h) }
            Spacer()
        }
    }

    private func ratingChip(label: String, rating: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                StarDisplayView(rating: rating)
                Text(String(format: "%.1f", rating))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func topItemRow(label: String, name: String, rating: Double?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            Spacer()
            if let r = rating { StarDisplayView(rating: r) }
        }
    }

    private func rideStatChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var spendingCard: some View {
        statsCard(title: "Spending", systemImage: "dollarsign.circle.fill", color: .green) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track food, merch & Lightning Lane spending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink("Open") { SpendingView() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var badgesTeaser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Badges", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Spacer()
                NavigationLink("See All") { BadgesView() }
                    .font(.subheadline)
            }

            Text("\(earnedBadges.count) of \(allBadges.count) earned")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !nextBadges.isEmpty {
                Text("Next to earn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(nextBadges) { badge in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Color(.systemFill))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: badge.systemImage)
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                                Text(badge.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 64)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
