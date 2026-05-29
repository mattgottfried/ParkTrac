import SwiftUI

struct WaitStopwatchSection: View {
    let ride: DisplayRide
    let postedWait: Int?         // ride.waitMinutes at the moment timing starts
    @Environment(AppState.self) private var appState
    @State private var elapsed: TimeInterval = 0
    let onSave: (Int, Int) -> Void  // (actualMinutes, postedMinutes)

    private var isTimingThisRide: Bool {
        appState.activeTimerRideId == ride.id
    }

    private var isTimingOtherRide: Bool {
        appState.activeTimerRideId != nil && !isTimingThisRide
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wait Stopwatch", systemImage: "stopwatch")
                .font(.headline)
                .foregroundStyle(.orange)

            if isTimingThisRide {
                // Live timer display
                let mins = Int(elapsed) / 60
                let secs = Int(elapsed) % 60
                Text(String(format: "%d:%02d", mins, secs))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                        if let start = appState.activeTimerStart {
                            elapsed = Date().timeIntervalSince(start)
                        }
                    }

                HStack(spacing: 12) {
                    Button("Done Waiting") {
                        let actualMins = max(1, Int(elapsed / 60))
                        let posted = postedWait ?? 0
                        onSave(actualMins, posted)
                        appState.activeTimerRideId = nil
                        appState.activeTimerStart = nil
                        elapsed = 0
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button("Cancel") {
                        appState.activeTimerRideId = nil
                        appState.activeTimerStart = nil
                        elapsed = 0
                    }
                    .buttonStyle(.bordered)
                }
            } else if isTimingOtherRide {
                Text("Another ride is being timed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    appState.activeTimerRideId = ride.id
                    appState.activeTimerStart = Date()
                    elapsed = 0
                } label: {
                    Label("Start Timer", systemImage: "stopwatch")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                if let posted = postedWait {
                    Text("Posted wait: \(posted) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if isTimingThisRide, let start = appState.activeTimerStart {
                elapsed = Date().timeIntervalSince(start)
            }
        }
    }
}
