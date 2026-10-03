import SwiftUI
import SwiftData

struct VisitHistoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \RideLog.riddenAt, order: .reverse) private var allLogs: [RideLog]
    @Query private var allPurchases: [PurchaseLog]
    @State private var crowdHistory = CrowdHistoryService.shared

    private var resortLogs: [RideLog] {
        allLogs.filter { $0.resort == appState.selectedResort.rawValue && !UndoDeleteCenter.shared.isHidden($0) }
    }

    private var visitDays: [VisitDay] {
        let cal = Calendar.current
        var byDay: [Date: [RideLog]] = [:]
        for log in resortLogs {
            let day = cal.startOfDay(for: log.riddenAt)
            byDay[day, default: []].append(log)
        }
        return byDay.map { VisitDay(id: $0.key, resort: appState.selectedResort.rawValue, entries: $0.value) }
            .sorted { $0.id > $1.id }
    }

    private var visitsByYear: [(year: Int, visits: [VisitDay])] {
        let cal = Calendar.current
        var byYear: [Int: [VisitDay]] = [:]
        for v in visitDays {
            let year = cal.component(.year, from: v.id)
            byYear[year, default: []].append(v)
        }
        return byYear.map { (year: $0.key, visits: $0.value.sorted { $0.id > $1.id }) }
            .sorted { $0.year > $1.year }
    }

    private var mostVisitedPark: String? {
        var counts: [String: Int] = [:]
        for visit in visitDays {
            for park in visit.parks { counts[park, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    /// By rides logged (not days visited, like `mostVisitedPark` above) — reuses `MostRiddenRide`'s
    /// generic "highest count" logic against park names instead of ride names.
    private var mostRiddenPark: (name: String, count: Int)? {
        MostRiddenRide.pick(counts: Dictionary(resortLogs.map { ($0.parkName, 1) }, uniquingKeysWith: +))
    }

    /// Consecutive years (ending at the most recent one with a logged visit) — "5 years running."
    private var annualStreak: Int {
        AnnualStreak.count(years: Set(resortLogs.map { Calendar.current.component(.year, from: $0.riddenAt) }))
    }

    private var avgRidesPerVisit: Double? {
        guard !visitDays.isEmpty else { return nil }
        return Double(resortLogs.count) / Double(visitDays.count)
    }

    /// Trips are inferred from the dates actually logged — no explicit trip boundary exists.
    private var trips: [VisitTrip] { VisitTripGrouper.group(visitDays) }
    private var tripComparison: TripComparison? { VisitTripGrouper.compareLatestToPrevious(trips) }
    private var spendComparison: SpendComparison? {
        let purchases = allPurchases
            .filter { $0.resort == appState.selectedResort.rawValue }
            .map { (amount: $0.amount, date: $0.date) }
        return SpendPaceComparer.compare(trips: trips, purchases: purchases)
    }

    /// This trip's single best day so far (most rides).
    private var tripHighlight: TripHighlightDay? {
        trips.last.flatMap(TripHighlight.bestDay)
    }

    /// Whether this trip is the quietest one yet, vs. every past trip.
    private var quietestTrip: QuietestTripResult? {
        let resort = appState.selectedResort
        guard let data = crowdHistory.days(for: resort) else { return nil }
        return QuietestTrip.compare(trips: trips) { date in CrowdHistory.level(for: date, resort: resort, data: data) }
    }

    var body: some View {
        List {
            if visitDays.isEmpty {
                ContentUnavailableView {
                    Label("No visits yet", systemImage: "calendar")
                } description: {
                    Text("Log rides with \"Rode It!\" and your visits will appear here.")
                } actions: {
                    Button("Open Wait Times") { DeepLinkRouter.shared.open(.waitTimes) }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                // Summary stats
                Section {
                    HStack(spacing: 16) {
                        statTile(value: "\(visitDays.count)", label: "Total Visits", color: .blue)
                        if let park = mostVisitedPark {
                            statTile(value: park, label: "Fav Park", color: .purple)
                        }
                        if let avg = avgRidesPerVisit {
                            statTile(value: String(format: "%.1f", avg), label: "Avg Rides", color: .green)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)

                    if let park = mostRiddenPark {
                        Label("Most rides at \(park.name) — \(park.count)", systemImage: "map.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if annualStreak >= 2 {
                        Label("\(annualStreak) years running", systemImage: "flame.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                if let comparison = tripComparison, let trip = trips.last, trip.dayCount > 0 {
                    Section {
                        tripComparisonCard(comparison, dayCount: trip.dayCount)
                        if let spend = spendComparison {
                            spendComparisonRow(spend)
                        }
                        if let highlight = tripHighlight {
                            Label(highlightText(highlight), systemImage: "star.fill")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        if let quietest = quietestTrip {
                            Label(quietestText(quietest), systemImage: "leaf.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                    .task {
                        await crowdHistory.refreshIfNeeded(resort: appState.selectedResort)
                    }
                }

                // Visits by year
                ForEach(visitsByYear, id: \.year) { section in
                    Section("\(section.year)  ·  \(section.visits.count) visit\(section.visits.count == 1 ? "" : "s")") {
                        ForEach(section.visits) { visit in
                            NavigationLink {
                                VisitDayDetailView(visit: visit)
                            } label: {
                                VisitDayRow(visit: visit)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Visit History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    /// "This trip so far" vs. the same number of days into the trip before it — inferred from
    /// gaps in the logged dates, since there's no explicit trip boundary.
    private func tripComparisonCard(_ comparison: TripComparison, dayCount: Int) -> some View {
        let dayWord = dayCount == 1 ? "day" : "days"
        return VStack(alignment: .leading, spacing: 6) {
            Label("This Trip So Far", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.blue)
            Text("\(comparison.currentRides) rides in \(dayCount) \(dayWord)"
                + (comparison.newRideNames.isEmpty ? "" : " (\(comparison.newRideNames.count) new)"))
                .font(.subheadline)
            HStack(spacing: 4) {
                Image(systemName: comparison.rideDifference >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(comparison.rideDifference >= 0 ? Color.green : Color.orange)
                Text("\(comparison.priorRidesByThisPoint) by this point last trip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !comparison.newRideNames.isEmpty {
                Text("New this trip: \(NameList.format(comparison.newRideNames, maxShown: 4))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func highlightText(_ highlight: TripHighlightDay) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "Best day so far: \(f.string(from: highlight.date)) — \(highlight.rideCount) ride\(highlight.rideCount == 1 ? "" : "s")"
    }

    private func quietestText(_ quietest: QuietestTripResult) -> String {
        "Quietest trip yet — lower crowds than your last \(quietest.tripsCompared) trip\(quietest.tripsCompared == 1 ? "" : "s")"
    }

    private func spendComparisonRow(_ spend: SpendComparison) -> some View {
        HStack(spacing: 4) {
            Image(systemName: spend.perDayDifference <= 0 ? "arrow.down.right" : "arrow.up.right")
                .foregroundStyle(spend.perDayDifference <= 0 ? Color.green : Color.orange)
            Text("\(spend.currentPerDay, format: .currency(code: appState.selectedResort.currencyCode))/day so far, vs. \(spend.previousPerDay, format: .currency(code: appState.selectedResort.currencyCode))/day last trip")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

// MARK: - Visit Day Row

private struct VisitDayRow: View {
    let visit: VisitDay

    private var dateStr: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: visit.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateStr)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                // Park chips
                ForEach(visit.parks, id: \.self) { park in
                    Text(park)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Spacer()

                Text("\(visit.totalRides) ride\(visit.totalRides == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Visit Day Detail

struct VisitDayDetailView: View {
    let visit: VisitDay

    @Environment(\.modelContext) private var context
    @State private var fullScreenPhoto: UIImage?
    @State private var weatherService = HistoricalWeatherService.shared

    private var resort: ParkGroup? { ParkGroup(rawValue: visit.resort) }
    private var weather: HistoricalWeatherDay? {
        resort.flatMap { weatherService.day(for: visit.id, resort: $0) }
    }

    private var dateStr: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: visit.id)
    }

    private var entriesByPark: [(park: String, logs: [RideLog])] {
        var byPark: [String: [RideLog]] = [:]
        // Deleted IDs stay hidden for the session, so this snapshot never touches a deleted model
        for log in visit.entries where !UndoDeleteCenter.shared.isHidden(log) {
            byPark[log.parkName, default: []].append(log)
        }
        return byPark.map { (park: $0.key, logs: $0.value.sorted { $0.riddenAt < $1.riddenAt }) }
            .sorted { $0.park < $1.park }
    }

    private func delete(_ log: RideLog) {
        UndoDeleteCenter.shared.delete([log], message: "Deleted \u{201C}\(log.rideName)\u{201D}", in: context)
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        List {
            Section {
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text("\(visit.totalRides)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.blue)
                        Text("Rides")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(visit.parks.count)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.purple)
                        Text(visit.parks.count == 1 ? "Park" : "Parks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let weather {
                        VStack(spacing: 2) {
                            let info = HistoricalWeather.describe(weather.weatherCode)
                            Image(systemName: info.icon).font(.title2).foregroundStyle(.orange)
                            Text("\(Int(weather.highF.rounded()))°F")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .task {
                    if let resort { await weatherService.fetchIfNeeded(for: visit.id, resort: resort) }
                }
            }

            if entriesByPark.isEmpty {
                ContentUnavailableView("No Rides Left", systemImage: "ticket",
                    description: Text("All rides for this visit have been removed."))
                    .listRowBackground(Color.clear)
            }

            ForEach(entriesByPark, id: \.park) { group in
                Section(group.park) {
                    ForEach(group.logs) { log in
                        HStack {
                            if let data = log.photoData, let image = UIImage(data: data) {
                                Button { fullScreenPhoto = image } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.rideName)
                                    .font(.subheadline)
                                if !log.notes.isEmpty {
                                    Text(log.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Self.timeFmt.string(from: log.riddenAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let wait = log.waitMinutes {
                                    Text("\(wait) min wait")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { delete(log) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(dateStr)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(
            get: { fullScreenPhoto.map { IdentifiableImage(image: $0) } },
            set: { fullScreenPhoto = $0?.image }
        )) { wrapped in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: wrapped.image)
                    .resizable()
                    .scaledToFit()
            }
            .onTapGesture { fullScreenPhoto = nil }
        }
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
