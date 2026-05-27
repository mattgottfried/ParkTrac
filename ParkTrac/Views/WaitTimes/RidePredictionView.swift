import SwiftUI
import Charts
import SwiftData

struct RidePredictionView: View {
    let ride: DisplayRide
    let parkGroup: ParkGroup
    let parkName: String
    @Environment(\.modelContext) private var modelContext

    @State private var prediction: PredictionResult?
    private let currentHour = Calendar.current.component(.hour, from: Date())

    init(ride: DisplayRide, parkGroup: ParkGroup, parkName: String = "") {
        self.ride = ride
        self.parkGroup = parkGroup
        self.parkName = parkName
    }

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
                parkName: parkName,
                currentStatus: ride.status,
                context: modelContext
            )
        }
    }

    // MARK: - Operating Ride Predictions

    private var operatingPredictions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Predictions", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let prediction {
                if prediction.hourlyAverages.count >= 3 {
                    waitChart(prediction.hourlyAverages)
                        .frame(height: 90)
                        .padding(.vertical, 4)

                    dataSourceLabel(prediction.dataSource)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text(prediction.bestTimeAdvice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let avg = prediction.historicalAverage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.blue)
                        Text("Historically ~\(avg) min at this time (\(prediction.historicalSampleCount) data points)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if case .none = prediction.dataSource {
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

    // MARK: - Chart

    @ViewBuilder
    private func waitChart(_ points: [HourlyAverage]) -> some View {
        let historical = points.filter { !$0.isProjected }
        let projected  = points.filter { $0.isProjected }

        Chart {
            ForEach(historical) { point in
                AreaMark(
                    x: .value("Hour", point.hour),
                    y: .value("Wait", point.averageWait)
                )
                .foregroundStyle(.blue.opacity(0.12))
                .interpolationMethod(.catmullRom)
            }

            ForEach(historical) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Wait", point.averageWait)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            ForEach(projected) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Wait", point.averageWait)
                )
                .foregroundStyle(.blue.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.catmullRom)
            }

            RuleMark(x: .value("Now", currentHour))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary.opacity(0.6))
                .annotation(position: .top, alignment: .center) {
                    Text("Now")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
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
    }

    @ViewBuilder
    private func dataSourceLabel(_ source: PredictionDataSource) -> some View {
        switch source {
        case .personalHistory(let count):
            HStack(spacing: 4) {
                Image(systemName: "person.fill").font(.caption2)
                Text("Based on your \(count) visits")
                    .font(.caption2)
            }
            .foregroundStyle(.blue.opacity(0.7))
        case .communityBaseline:
            HStack(spacing: 4) {
                Image(systemName: "person.3").font(.caption2)
                Text("Based on community data")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Down Ride Predictions

    private var downPredictions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Closure Info", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            if let prediction {
                if let avg = prediction.closureAverageDuration, avg > 0,
                   let pct = prediction.closureProgressPct {
                    // Visual progress bar
                    closureProgressBar(
                        elapsed: prediction.closureElapsedMinutes ?? 0,
                        average: avg,
                        pct: pct,
                        isOverdue: prediction.closureIsOverdue,
                        sampleCount: prediction.closureSampleCount
                    )
                } else if let elapsed = prediction.closureElapsedMinutes {
                    // We know elapsed but no average yet
                    HStack(spacing: 8) {
                        Image(systemName: "timer").foregroundStyle(.orange)
                        Text("Down for \(elapsed) minute\(elapsed == 1 ? "" : "s")")
                            .font(.subheadline.weight(.medium))
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                        Text(prediction.closureSampleCount > 0
                             ? "Building closure history (\(prediction.closureSampleCount) past closures — need 3 for estimate)"
                             : "Not enough closure history yet for an estimate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // No open DowntimeRecord found — show plain text
                    if let avg = prediction.closureAverageDuration {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                            Text("Usually back in ~\(avg) min (based on \(prediction.closureSampleCount) past closures)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                            Text("Not enough closure history yet for an estimate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func closureProgressBar(
        elapsed: Int,
        average: Int,
        pct: Double,
        isOverdue: Bool,
        sampleCount: Int
    ) -> some View {
        let clampedPct = min(pct, 1.5)
        let barColor: Color = {
            if pct < 0.6 { return .green }
            if pct < 1.0 { return .orange }
            return .red
        }()

        VStack(alignment: .leading, spacing: 8) {
            // Elapsed time headline
            HStack(spacing: 8) {
                Image(systemName: "timer").foregroundStyle(.orange)
                Text("Down for \(elapsed) minute\(elapsed == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                if isOverdue {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.15))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * clampedPct / 1.5, height: 8)
                        .animation(.easeInOut(duration: 0.4), value: clampedPct)
                }
            }
            .frame(height: 8)

            // Labels under bar
            HStack {
                Text(isOverdue ? "Running longer than usual" : (pct > 0.75 ? "Should reopen soon" : "On track"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(barColor)
                Spacer()
                Text("\(elapsed)/\(average) min  (\(Int(pct * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Based on \(sampleCount) past closure\(sampleCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return hour < 12 ? "\(h)am" : "\(h)pm"
    }
}
