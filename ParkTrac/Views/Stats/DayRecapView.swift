import SwiftUI
import SwiftData
import CoreMotion

// MARK: - Recap (pure, unit tested)

/// One park day at a glance: rides, time in line vs posted, the best-timed ride, money spent
/// and steps. Built from Rode It! logs and purchases, so any past day can be recapped.
struct DayRecap: Equatable {
    struct Ride: Equatable {
        let name: String
        let posted: Int?
        let actual: Int?
        let at: Date
    }

    let date: Date
    let resortName: String
    let rides: [Ride]
    let spent: Double
    let currencyCode: String
    var steps: Int? = nil
    var distanceMeters: Double? = nil

    var rideCount: Int { rides.count }
    var uniqueRides: Int { Set(rides.map(\.name)).count }

    /// Today's spend divided by rides ridden — a fun stat, not a precise one (spend includes
    /// food/merch/tickets, not just per-ride costs).
    var costPerRide: Double? {
        guard spent > 0, rideCount > 0 else { return nil }
        return spent / Double(rideCount)
    }

    /// Minutes spent in line: timed waits where you timed them, else the posted wait
    var minutesInLine: Int { rides.reduce(0) { $0 + ($1.actual ?? $1.posted ?? 0) } }

    /// Posted − actual over the rides you timed (positive = you beat the signs)
    var beatPostedBy: Int? {
        let pairs = rides.compactMap { r -> Int? in
            guard let p = r.posted, let a = r.actual else { return nil }
            return p - a
        }
        return pairs.isEmpty ? nil : pairs.reduce(0, +)
    }

    /// The ride that beat its posted wait by the most, else the shortest posted wait
    var bestRide: (name: String, text: String)? {
        let wins = rides.compactMap { r -> (name: String, saved: Int, posted: Int, actual: Int)? in
            guard let p = r.posted, let a = r.actual, p > a else { return nil }
            return (name: r.name, saved: p - a, posted: p, actual: a)
        }
        if let best = wins.max(by: { $0.saved < $1.saved }) {
            return (name: best.name, text: "Waited \(best.actual) min, posted \(best.posted)")
        }
        let posted = rides.compactMap { r -> (name: String, wait: Int)? in r.posted.map { (name: r.name, wait: $0) } }
        if let shortest = posted.min(by: { $0.wait < $1.wait }) {
            return (name: shortest.name, text: "Only \(shortest.wait) min posted")
        }
        return nil
    }

    /// Ridden more than once
    var mostRidden: (name: String, count: Int)? {
        let counts = Dictionary(rides.map { ($0.name, 1) }, uniquingKeysWith: +)
        guard let top = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }),
              top.value > 1 else { return nil }
        return (name: top.key, count: top.value)
    }

    static func == (lhs: DayRecap, rhs: DayRecap) -> Bool {
        lhs.date == rhs.date && lhs.resortName == rhs.resortName && lhs.rides == rhs.rides
            && lhs.spent == rhs.spent && lhs.steps == rhs.steps && lhs.distanceMeters == rhs.distanceMeters
    }
}

enum DayRecapBuilder {
    struct LogRow {
        let name: String
        let posted: Int?
        let actual: Int?
        let at: Date
        let resort: String
    }

    struct Purchase {
        let amount: Double
        let date: Date
        let resort: String
    }

    static func make(date: Date, resort: ParkGroup, logs: [LogRow], purchases: [Purchase],
                     calendar: Calendar = .current) -> DayRecap {
        let rides = logs
            .filter { $0.resort == resort.rawValue && calendar.isDate($0.at, inSameDayAs: date) }
            .sorted { $0.at < $1.at }
            .map { DayRecap.Ride(name: $0.name, posted: $0.posted, actual: $0.actual, at: $0.at) }
        let spent = purchases
            .filter { $0.resort == resort.rawValue && calendar.isDate($0.date, inSameDayAs: date) }
            .map(\.amount)
            .reduce(0, +)
        return DayRecap(date: calendar.startOfDay(for: date), resortName: resort.rawValue, rides: rides,
                        spent: spent, currencyCode: resort.currencyCode)
    }

    /// Days with at least one ride logged at the resort, newest first
    static func days(logs: [LogRow], resort: ParkGroup, calendar: Calendar = .current) -> [Date] {
        let days = Set(logs.filter { $0.resort == resort.rawValue }.map { calendar.startOfDay(for: $0.at) })
        return days.sorted(by: >)
    }
}

extension RideLog {
    var recapRow: DayRecapBuilder.LogRow {
        DayRecapBuilder.LogRow(name: rideName, posted: waitMinutes, actual: actualWaitMinutes, at: riddenAt, resort: resort)
    }
}

// MARK: - Year in Review (pure)

/// One calendar year across every trip logged at a resort — a bigger, once-a-year sibling of
/// `DayRecap`. Trip count reuses `VisitTripGrouper` (gaps between visit days infer trips);
/// top ride reuses `MostRiddenRide`.
struct YearRecap {
    let year: Int
    let resortName: String
    let rideCount: Int
    let uniqueRides: Int
    let daysVisited: Int
    let tripCount: Int
    let topRide: (name: String, count: Int)?
    let spent: Double
    let currencyCode: String
}

enum YearRecapBuilder {
    static func make(year: Int, resort: ParkGroup, logs: [DayRecapBuilder.LogRow],
                     purchases: [DayRecapBuilder.Purchase], calendar: Calendar = .current) -> YearRecap {
        let yearLogs = logs.filter { $0.resort == resort.rawValue && calendar.component(.year, from: $0.at) == year }
        let dayKeys = Set(yearLogs.map { calendar.startOfDay(for: $0.at) })
        let visitDays = dayKeys.map { VisitDay(id: $0, resort: resort.rawValue, entries: []) }
        let trips = VisitTripGrouper.group(visitDays)
        let spent = purchases
            .filter { $0.resort == resort.rawValue && calendar.component(.year, from: $0.date) == year }
            .map(\.amount).reduce(0, +)
        return YearRecap(
            year: year, resortName: resort.rawValue,
            rideCount: yearLogs.count,
            uniqueRides: Set(yearLogs.map(\.name)).count,
            daysVisited: dayKeys.count,
            tripCount: trips.count,
            topRide: MostRiddenRide.pick(counts: Dictionary(yearLogs.map { ($0.name, 1) }, uniquingKeysWith: +)),
            spent: spent, currencyCode: resort.currencyCode)
    }

    /// Years with at least one ride logged at the resort, newest first.
    static func years(logs: [DayRecapBuilder.LogRow], resort: ParkGroup, calendar: Calendar = .current) -> [Int] {
        Set(logs.filter { $0.resort == resort.rawValue }.map { calendar.component(.year, from: $0.at) }).sorted(by: >)
    }
}

// MARK: - Steps (Core Motion — the phone keeps about a week)

enum StepCounter {
    private static let pedometer = CMPedometer()

    static func steps(on date: Date, calendar: Calendar = .current) async -> (steps: Int, meters: Double?)? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let start = calendar.startOfDay(for: date)
        guard Date.now.timeIntervalSince(start) < 7 * 86_400,
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let end = min(dayEnd, Date.now)
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (steps: data.numberOfSteps.intValue, meters: data.distance?.doubleValue))
            }
        }
    }
}

// MARK: - Recap screen

struct DayRecapView: View {
    let date: Date
    let resort: ParkGroup

    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [RideLog]
    @Query private var purchases: [PurchaseLog]
    @State private var steps: (steps: Int, meters: Double?)?
    @State private var shareImage: Image?

    private var recap: DayRecap {
        var r = DayRecapBuilder.make(
            date: date, resort: resort, logs: logs.map(\.recapRow),
            purchases: purchases.map { DayRecapBuilder.Purchase(amount: $0.amount, date: $0.date, resort: $0.resort) })
        r.steps = steps?.steps
        r.distanceMeters = steps?.meters
        return r
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RecapCard(recap: recap)

                if !recap.rides.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rides").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(recap.rides.enumerated()), id: \.offset) { _, ride in
                            HStack {
                                Text(ride.at.formatted(date: .omitted, time: .shortened))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(ride.name).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(waitText(ride)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 10) {
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("My ThrillTrack day", image: shareImage)) {
                            Label("Share Card", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ShareLink(item: summaryText) {
                        Label("Share Text", systemImage: "text.alignleft")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Calendar.current.isDateInToday(date) ? "Today's Recap" : "Day Recap")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            steps = await StepCounter.steps(on: date)
            renderShareImage()
        }
        .onChange(of: logs.count) { _, _ in renderShareImage() }
    }

    private func waitText(_ ride: DayRecap.Ride) -> String {
        switch (ride.posted, ride.actual) {
        case let (p?, a?): return "\(a) min · posted \(p)"
        case let (p?, nil): return "posted \(p) min"
        case let (nil, a?): return "\(a) min"
        case (nil, nil): return ""
        }
    }

    private var summaryText: String {
        DaySummary.text(date: date, resort: resort.rawValue,
                        rides: recap.rides.map { DaySummary.Ride(name: $0.name, postedWait: $0.posted, actualWait: $0.actual) },
                        planDone: 0, planTotal: 0, spent: recap.spent, currencyCode: recap.currencyCode)
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(content: RecapCard(recap: recap).frame(width: 360).padding(12)
            .background(Color.black))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

/// The shareable card
struct RecapCard: View {
    let recap: DayRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recap.date.formatted(date: .complete, time: .omitted))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(recap.resortName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                stat("\(recap.rideCount)", "rides", icon: "figure.jumprope")
                stat(hours(recap.minutesInLine), "in line", icon: "clock.fill")
                if let steps = recap.steps {
                    stat(steps.formatted(.number.notation(.compactName)), "steps", icon: "shoeprints.fill")
                } else if recap.spent > 0 {
                    stat(recap.spent.formatted(.currency(code: recap.currencyCode).precision(.fractionLength(0))),
                         "spent", icon: "creditcard.fill")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let beat = recap.beatPostedBy {
                    line(icon: beat >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                         text: beat >= 0 ? "Beat the posted waits by \(beat) min" : "Waited \(-beat) min longer than posted")
                }
                if let best = recap.bestRide {
                    line(icon: "star.fill", text: "Best timing: \(best.name) — \(best.text)")
                }
                if let most = recap.mostRidden {
                    line(icon: "repeat", text: "\(most.name) × \(most.count)")
                }
                if let meters = recap.distanceMeters, meters > 0 {
                    line(icon: "figure.walk",
                         text: "Walked \(Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))")
                }
                if recap.steps != nil && recap.spent > 0 {
                    line(icon: "creditcard.fill",
                         text: "Spent \(recap.spent.formatted(.currency(code: recap.currencyCode)))")
                }
                if let perRide = recap.costPerRide {
                    line(icon: "divide.circle.fill",
                         text: "\(perRide.formatted(.currency(code: recap.currencyCode))) per ride today")
                }
                if recap.rides.isEmpty {
                    line(icon: "info.circle", text: "Log rides with Rode It! and they'll show up here.")
                }
            }

            HStack {
                Spacer()
                Text("ThrillTrack").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func line(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
    }

    /// 95 → "1h 35m", 40 → "40m"
    private func hours(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

// MARK: - Year in Review screen

struct YearRecapView: View {
    let year: Int
    let resort: ParkGroup

    @Query private var logs: [RideLog]
    @Query private var purchases: [PurchaseLog]
    @State private var shareImage: Image?

    private var recap: YearRecap {
        YearRecapBuilder.make(year: year, resort: resort, logs: logs.map(\.recapRow),
                              purchases: purchases.map { DayRecapBuilder.Purchase(amount: $0.amount, date: $0.date, resort: $0.resort) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                YearRecapCard(recap: recap)

                ShareLink(item: summaryText) {
                    Label("Share Text", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(String(year)) in Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryText: String {
        var lines = ["\(recap.resortName) — \(recap.year) in Review",
                     "\(recap.rideCount) rides across \(recap.daysVisited) day\(recap.daysVisited == 1 ? "" : "s")"]
        if recap.tripCount > 0 { lines.append("\(recap.tripCount) trip\(recap.tripCount == 1 ? "" : "s")") }
        if let top = recap.topRide { lines.append("Top ride: \(top.name) × \(top.count)") }
        if recap.spent > 0 {
            lines.append("Spent \(recap.spent.formatted(.currency(code: recap.currencyCode)))")
        }
        return lines.joined(separator: "\n")
    }
}

private struct YearRecapCard: View {
    let recap: YearRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(recap.year)) in Review")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(recap.resortName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                stat("\(recap.rideCount)", "rides", icon: "figure.jumprope")
                stat("\(recap.daysVisited)", "days", icon: "calendar")
                stat("\(recap.tripCount)", "trips", icon: "airplane")
            }

            VStack(alignment: .leading, spacing: 8) {
                if let top = recap.topRide {
                    Label("Top ride: \(top.name) × \(top.count)", systemImage: "trophy.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                }
                Label("\(recap.uniqueRides) unique rides", systemImage: "list.star")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                if recap.spent > 0 {
                    Label("Spent \(recap.spent.formatted(.currency(code: recap.currencyCode)))",
                          systemImage: "creditcard.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                }
                if recap.rideCount == 0 {
                    Label("No rides logged this year yet.", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                }
            }

            HStack {
                Spacer()
                Text("ThrillTrack").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Past recaps (Stats)

struct DayRecapListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \RideLog.riddenAt, order: .reverse) private var logs: [RideLog]

    var body: some View {
        let resort = appState.selectedResort
        let days = DayRecapBuilder.days(logs: logs.map(\.recapRow), resort: resort)
        let years = YearRecapBuilder.years(logs: logs.map(\.recapRow), resort: resort)
        List {
            if days.isEmpty {
                ContentUnavailableView("No Park Days Yet", systemImage: "sparkles",
                                       description: Text("Log rides with Rode It! and each day gets a recap here."))
            }
            if !years.isEmpty {
                Section("Year in Review") {
                    ForEach(years, id: \.self) { year in
                        NavigationLink {
                            YearRecapView(year: year, resort: resort)
                        } label: {
                            Label("\(String(year)) in Review", systemImage: "sparkles")
                        }
                    }
                }
            }
            ForEach(days, id: \.self) { day in
                NavigationLink {
                    DayRecapView(date: day, resort: resort)
                } label: {
                    HStack {
                        Text(day.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        let count = logs.filter { $0.resort == resort.rawValue && Calendar.current.isDate($0.riddenAt, inSameDayAs: day) }.count
                        Text("\(count) ride\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Day Recaps")
    }
}
