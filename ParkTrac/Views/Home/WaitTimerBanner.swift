import SwiftUI
import SwiftData

struct WaitTimerBanner: View {
    let appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsed: TimeInterval {
        guard let start = appState.timerStartDate else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    private var elapsedDisplay: String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.timerRideName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("Posted: \(appState.timerPostedMinutes)m")
                    Text("·")
                    Text(elapsedDisplay)
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { finish() }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.green, in: Capsule())
                .foregroundStyle(.white)
                .buttonStyle(.plain)

            Button { appState.clearTimer() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .onReceive(ticker) { now = $0 }
    }

    private func finish() {
        guard let start = appState.timerStartDate else { appState.clearTimer(); return }
        let actualMinutes = max(1, Int(Date().timeIntervalSince(start) / 60))
        let log = WaitTimerLog(
            rideId: appState.timerRideId ?? "",
            rideName: appState.timerRideName,
            resort: appState.timerResort,
            postedMinutes: appState.timerPostedMinutes,
            actualMinutes: actualMinutes,
            startedAt: start
        )
        modelContext.insert(log)
        try? modelContext.save()
        appState.clearTimer()
    }
}
