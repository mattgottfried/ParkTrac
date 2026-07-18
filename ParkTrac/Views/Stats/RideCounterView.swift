import SwiftUI
import SwiftData

struct RideCounterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \RideLog.riddenAt, order: .reverse) private var allLogs: [RideLog]

    @State private var sortByCount = true

    private var resortLogs: [RideLog] {
        allLogs.filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var totalThisYear: Int {
        let startOfYear = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: .now))!
        return resortLogs.filter { $0.riddenAt >= startOfYear }.count
    }

    /// Group logs by rideName, sorted by count or recency
    private var rideGroups: [(name: String, parkName: String, count: Int, lastRidden: Date)] {
        var dict: [String: (parkName: String, count: Int, lastRidden: Date)] = [:]
        for log in resortLogs {
            if let existing = dict[log.rideName] {
                dict[log.rideName] = (
                    parkName: existing.parkName,
                    count: existing.count + 1,
                    lastRidden: max(existing.lastRidden, log.riddenAt)
                )
            } else {
                dict[log.rideName] = (parkName: log.parkName, count: 1, lastRidden: log.riddenAt)
            }
        }
        let groups = dict.map { (name: $0.key, parkName: $0.value.parkName, count: $0.value.count, lastRidden: $0.value.lastRidden) }
        if sortByCount {
            return groups.sorted { $0.count != $1.count ? $0.count > $1.count : $0.lastRidden > $1.lastRidden }
        } else {
            return groups.sorted { $0.lastRidden > $1.lastRidden }
        }
    }

    var body: some View {
        List {
            if resortLogs.isEmpty {
                ContentUnavailableView(
                    "No rides logged yet",
                    systemImage: "ticket",
                    description: Text("Tap \u{201C}Rode It!\u{201D} on any ride to start tracking.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack(spacing: 24) {
                        statChip(value: "\(resortLogs.count)", label: "All Time", color: .blue)
                        statChip(value: "\(totalThisYear)", label: "This Year", color: .green)
                        statChip(value: "\(rideGroups.count)", label: "Unique Rides", color: .purple)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)
                }

                Section("All Rides") {
                    ForEach(rideGroups, id: \.name) { group in
                        RideCountRow(
                            rideName: group.name,
                            parkName: group.parkName,
                            count: group.count,
                            lastRidden: group.lastRidden
                        )
                        .swipeActions {
                            Button("Delete All", role: .destructive) {
                                deleteAllLogs(named: group.name)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ride Counter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sortByCount = true
                    } label: {
                        Label("Sort by Count", systemImage: sortByCount ? "checkmark" : "")
                    }
                    Button {
                        sortByCount = false
                    } label: {
                        Label("Sort by Recency", systemImage: sortByCount ? "" : "checkmark")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func deleteAllLogs(named rideName: String) {
        for log in resortLogs where log.rideName == rideName {
            context.delete(log)
        }
        try? context.save()
    }

    private func statChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RideCountRow: View {
    let rideName: String
    let parkName: String
    let count: Int
    let lastRidden: Date

    private var daysAgo: String {
        let days = Calendar.current.dateComponents([.day], from: lastRidden, to: .now).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Count badge
            ZStack {
                Circle()
                    .fill(countColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text("\(count)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(countColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rideName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("Last: \(daysAgo)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var countColor: Color {
        if count >= 20 { return .red }
        if count >= 10 { return .orange }
        if count >= 5  { return .yellow }
        return .green
    }
}
