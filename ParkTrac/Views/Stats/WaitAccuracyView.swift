import SwiftUI
import SwiftData

struct WaitAccuracyView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \WaitTimerLog.startedAt, order: .reverse) private var allLogs: [WaitTimerLog]

    private struct RideAccuracy: Identifiable {
        let id: String          // rideName
        let rideName: String
        let count: Int
        let avgPosted: Double
        let avgActual: Double
        var avgDelta: Double { avgActual - avgPosted }
        var pctDiff: Double { avgPosted > 0 ? (avgDelta / avgPosted * 100) : 0 }
    }

    private var resortLogs: [WaitTimerLog] {
        allLogs.filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var accuracyByRide: [RideAccuracy] {
        var grouped: [String: [WaitTimerLog]] = [:]
        for log in resortLogs { grouped[log.rideName, default: []].append(log) }
        return grouped.map { rideName, logs in
            RideAccuracy(
                id: rideName,
                rideName: rideName,
                count: logs.count,
                avgPosted: Double(logs.map(\.postedMinutes).reduce(0, +)) / Double(logs.count),
                avgActual: Double(logs.map(\.actualMinutes).reduce(0, +)) / Double(logs.count)
            )
        }
        .sorted { $0.count > $1.count }
    }

    private var overallAvgDelta: Double? {
        guard !resortLogs.isEmpty else { return nil }
        let total = resortLogs.map { Double($0.actualMinutes - $0.postedMinutes) }.reduce(0, +)
        return total / Double(resortLogs.count)
    }

    var body: some View {
        List {
            if resortLogs.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No wait times recorded yet.")
                            .font(.subheadline)
                        Text("Tap \"Time My Wait\" on any ride detail to start tracking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                if let delta = overallAvgDelta {
                    Section("Overall") {
                        HStack {
                            Label("\(resortLogs.count) timed rides", systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            deltaLabel(delta)
                        }
                    }
                }

                Section("By Ride") {
                    ForEach(accuracyByRide) { ride in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ride.rideName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                deltaLabel(ride.avgDelta)
                            }
                            HStack(spacing: 16) {
                                statChip(label: "Posted", value: "\(Int(ride.avgPosted.rounded()))m", color: .blue)
                                statChip(label: "Actual", value: "\(Int(ride.avgActual.rounded()))m", color: .orange)
                                statChip(label: "Samples", value: "\(ride.count)", color: .secondary)
                            }
                            Text(insight(for: ride))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Wait Accuracy")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func deltaLabel(_ delta: Double) -> some View {
        let abs = Swift.abs(delta)
        let over = delta > 0
        let color: Color = over ? .red : .green
        let symbol = over ? "clock.badge.exclamationmark" : "clock.badge.checkmark"
        Label(String(format: "%+.0fm avg", delta), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    private func statChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func insight(for ride: RideAccuracy) -> String {
        let absDelta = Swift.abs(ride.avgDelta)
        let absPct   = Swift.abs(ride.pctDiff)
        if absDelta < 2 { return "Posted times are accurate for this ride." }
        let dir = ride.avgDelta > 0 ? "over-posted by" : "under-posted by"
        return "Usually \(dir) ~\(Int(absDelta.rounded())) min (\(Int(absPct.rounded()))%)."
    }
}
