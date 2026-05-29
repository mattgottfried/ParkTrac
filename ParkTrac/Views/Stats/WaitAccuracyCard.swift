import SwiftUI
import SwiftData

struct WaitAccuracyCard: View {
    @Query private var allLogs: [RideLog]
    @Environment(AppState.self) private var appState

    private var timedLogs: [RideLog] {
        allLogs.filter { $0.actualWaitMinutes != nil && $0.waitMinutes != nil }
            .filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var avgPosted: Double? {
        guard !timedLogs.isEmpty else { return nil }
        return Double(timedLogs.compactMap(\.waitMinutes).reduce(0, +)) / Double(timedLogs.count)
    }

    private var avgActual: Double? {
        guard !timedLogs.isEmpty else { return nil }
        return Double(timedLogs.compactMap(\.actualWaitMinutes).reduce(0, +)) / Double(timedLogs.count)
    }

    var body: some View {
        // Only show when there's data
        if timedLogs.count >= 1 {
            VStack(alignment: .leading, spacing: 12) {
                Label("Wait Time Accuracy", systemImage: "stopwatch")
                    .font(.headline)
                    .foregroundStyle(.orange)

                if timedLogs.count < 3 {
                    Text("Time \(3 - timedLogs.count) more ride\(3 - timedLogs.count == 1 ? "" : "s") to see accuracy stats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let posted = avgPosted, let actual = avgActual {
                    HStack(spacing: 16) {
                        statPill(value: String(format: "%.0f min", posted), label: "Avg Posted", color: .blue)
                        statPill(value: String(format: "%.0f min", actual), label: "Avg Actual", color: .orange)
                        let diff = actual - posted
                        statPill(
                            value: String(format: "%+.0f min", diff),
                            label: diff >= 0 ? "Usually longer" : "Usually shorter",
                            color: diff >= 0 ? .red : .green
                        )
                    }
                }

                Text("\(timedLogs.count) ride\(timedLogs.count == 1 ? "" : "s") timed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Recent comparisons
                let recent = timedLogs.sorted { $0.riddenAt > $1.riddenAt }.prefix(3)
                ForEach(Array(recent), id: \.persistentModelID) { log in
                    HStack {
                        Text(log.rideName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if let posted = log.waitMinutes, let actual = log.actualWaitMinutes {
                            Text("\(posted)m posted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(actual)m actual")
                                .font(.caption)
                                .foregroundStyle(actual < posted ? .green : actual > posted ? .red : .primary)
                        }
                    }
                }
            }
            .padding()
            .background(appState.selectedResort.theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(appState.selectedResort.theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
        }
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.body, design: .rounded, weight: .bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
