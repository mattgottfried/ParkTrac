import SwiftUI
import SwiftData

struct VisitHistoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \RideLog.riddenAt, order: .reverse) private var allLogs: [RideLog]

    private var resortLogs: [RideLog] {
        allLogs.filter { $0.resort == appState.selectedResort.rawValue }
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

    private var avgRidesPerVisit: Double? {
        guard !visitDays.isEmpty else { return nil }
        return Double(resortLogs.count) / Double(visitDays.count)
    }

    var body: some View {
        List {
            if visitDays.isEmpty {
                ContentUnavailableView(
                    "No visits yet",
                    systemImage: "calendar",
                    description: Text("Log rides with \"Rode It!\" and your visits will appear here.")
                )
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

    private var dateStr: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: visit.id)
    }

    private var entriesByPark: [(park: String, logs: [RideLog])] {
        var byPark: [String: [RideLog]] = [:]
        for log in visit.entries {
            byPark[log.parkName, default: []].append(log)
        }
        return byPark.map { (park: $0.key, logs: $0.value.sorted { $0.riddenAt < $1.riddenAt }) }
            .sorted { $0.park < $1.park }
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
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            ForEach(entriesByPark, id: \.park) { group in
                Section(group.park) {
                    ForEach(group.logs) { log in
                        HStack {
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
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(dateStr)
        .navigationBarTitleDisplayMode(.inline)
    }
}
