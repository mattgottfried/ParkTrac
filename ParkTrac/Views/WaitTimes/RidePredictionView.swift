import SwiftUI
import Charts
import SwiftData

struct RidePredictionView: View {
    let ride: DisplayRide
    let parkGroup: ParkGroup
    @Environment(\.modelContext) private var modelContext

    @State private var prediction: PredictionResult?
    @State private var minutesDown: Int?

    var body: some View {
        Group {
            if ride.isOperating {
                operatingPredictions
            } else if ride.status == "DOWN" {
                downPredictions
            }
        }
        .task {
            prediction = WaitTimePredictionService.predict(
                rideId: ride.id,
                parkGroup: parkGroup,
                context: modelContext
            )
            if ride.status == "DOWN" {
                minutesDown = WaitTimeRecorder.shared.minutesDown(for: ride.id, context: modelContext)
            }
        }
    }

    // MARK: - Operating Ride Predictions

    private var operatingPredictions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Predictions", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let prediction {
                // Sparkline chart if we have hourly data
                if prediction.hourlyAverages.count >= 3 {
                    Chart(prediction.hourlyAverages) { point in
                        LineMark(
                            x: .value("Hour", point.hour),
                            y: .value("Wait", point.averageWait)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Hour", point.hour),
                            y: .value("Wait", point.averageWait)
                        )
                        .foregroundStyle(.blue.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: [8, 12, 16, 20]) { value in
                            AxisValueLabel {
                                if let h = value.as(Int.self) {
                                    Text(hourLabel(h))
                                }
                            }
                        }
                    }
                    .frame(height: 80)
                    .padding(.vertical, 4)
                }

                // General wisdom tip
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text(prediction.bestTimeAdvice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Personal history
                if let avg = prediction.historicalAverage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.blue)
                        Text("Historically ~\(avg) min at this time (\(prediction.historicalSampleCount) data points)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Visit more often to build personal wait time history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Down Ride Predictions

    private var downPredictions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Closure Info", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            if let mins = minutesDown {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                    Text("Down for \(mins) minute\(mins == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                }
            }

            if let prediction, let avgDuration = prediction.closureAverageDuration {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                    Text("Usually back in ~\(avgDuration) min (based on \(prediction.closureSampleCount) past closures)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                    Text("Not enough closure history yet for an estimate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return hour < 12 ? "\(h)am" : "\(h)pm"
    }
}
