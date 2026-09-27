import SwiftUI
import Charts
import SwiftData

struct RidePredictionView: View {
    /// Chart annotations stay compact but still follow Dynamic Type
    @ScaledMetric(relativeTo: .caption2) private var chartLabelSize: CGFloat = 8
    let ride: DisplayRide
    let parkGroup: ParkGroup
    let parkName: String
    @Environment(\.modelContext) private var modelContext

    @Environment(WaitTimesViewModel.self) private var viewModel

    @State private var prediction: PredictionResult?
    /// This ride's expected wait per hour today (same numbers as the Smart Planner / Tip Board)
    @State private var profile: [Int: Int] = [:]
    @State private var usualNow: Int?
    /// Server's typical waits for this ride on this weekday (empty until it has two days of data)
    @State private var community: [Int: Int] = [:]
    /// Hour the guest is touching on the chart
    @State private var selectedHour: Int?
    private let currentHour = Calendar.current.component(.hour, from: Date())

    /// What you really wait right now, from your stopwatch logs (`WaitReality`), when it differs
    let realWait: Int?

    init(ride: DisplayRide, parkGroup: ParkGroup, parkName: String = "", realWait: Int? = nil) {
        self.ride = ride
        self.parkGroup = parkGroup
        self.parkName = parkName
        self.realWait = realWait
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
            let parks = viewModel.parksByGroup[parkGroup] ?? []
            profile = PlanInputs.planRides([ride], parks: parks, fallbackParkName: parkName, context: modelContext)
                .first?.waitByHour ?? [:]
            let history = PlanInputs.history(for: [ride.id], days: 14, context: modelContext)
            community = CommunityHistoryService.shared.waitsByHour(rideId: ride.id, parkId: ride.parkId)
            // This phone's own history first, else what the server has seen at this hour on this weekday
            usualNow = GoodTimeToRide.usual(samples: history[ride.id] ?? [], community: community[currentHour])?.minutes
        }
    }

    // MARK: - Park hours

    private var todaysHours: [ParkScheduleDay] {
        guard let park = (viewModel.parksByGroup[parkGroup] ?? []).first(where: { $0.id == ride.parkId }) else { return [] }
        return viewModel.todaySchedule(for: park)
    }

    private var openHour: Int? {
        todaysHours.filter { !$0.isTicketedEvent && !$0.isExtraHours }
            .compactMap(\.openingDate).min()
            .map { Calendar.current.component(.hour, from: $0) }
    }

    private var lastHour: Int {
        WaitForecast.lastHour(closing: todaysHours.filter { !$0.isTicketedEvent }.compactMap(\.closingDate).max()) ?? 21
    }

    private var bars: [WaitForecast.Bar] {
        WaitForecast.bars(profile: profile, openHour: openHour, lastHour: lastHour)
    }

    // MARK: - Operating Ride Predictions

    private var operatingPredictions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Wait Forecast", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                if let prediction { sourceLabel(prediction.dataSource) }
            }

            if let call = WaitForecast.call(profile: profile, nowHour: currentHour,
                                            currentWait: ride.waitMinutes, lastHour: lastHour) {
                callRow(call)
            }

            if bars.count >= 3 {
                selectionCaption
                waitChart(bars)
                    .frame(height: 130)
            } else if let prediction {
                // Too little data for a chart — the general rule of thumb for this resort
                tipRow(icon: "lightbulb.fill", color: .yellow, text: prediction.bestTimeAdvice)
            }

            if let trend = WaitForecast.trend(profile: profile, nowHour: currentHour,
                                              currentWait: ride.waitMinutes, lastHour: lastHour) {
                switch trend {
                case .rising(let hour, let wait):
                    tipRow(icon: "arrow.up.right", color: .red,
                           text: "Getting longer — about \(wait) min by \(hourLabel(hour))")
                case .falling(let hour, let wait):
                    tipRow(icon: "arrow.down.right", color: .green,
                           text: "Getting shorter — about \(wait) min by \(hourLabel(hour))")
                }
            }

            if let usualNow, let wait = ride.waitMinutes {
                let diff = wait - usualNow
                tipRow(icon: "clock.arrow.circlepath", color: .blue,
                       text: abs(diff) < 5
                        ? "About normal for this time (usually ~\(usualNow) min)"
                        : "\(abs(diff)) min \(diff < 0 ? "shorter" : "longer") than usual for this time (~\(usualNow) min)")
            } else if let prediction, case .none = prediction.dataSource {
                tipRow(icon: "clock.arrow.circlepath", color: .secondary,
                       text: "The forecast gets personal as ThrillTrack records waits on your visits")
            }
        }
    }

    /// The headline: go now, or wait for a better hour.
    @ViewBuilder
    private func callRow(_ call: WaitForecast.Call) -> some View {
        let style = callStyle(call)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .font(.title3)
                .foregroundStyle(style.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title).font(.subheadline.weight(.semibold))
                Text(style.detail).font(.caption).foregroundStyle(.secondary)
                if let realWait, case .goNow = call {
                    Text("You usually wait ~\(realWait) min in this line")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(style.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func callStyle(_ call: WaitForecast.Call) -> (icon: String, color: Color, title: String, detail: String) {
        switch call {
        case .goNow(let wait):
            return (icon: "checkmark.circle.fill", color: .green, title: "Good time to go now",
                    detail: "~\(wait) min is about as short as it gets for the rest of today")
        case .waitUntil(let hour, let wait, let saves):
            return (icon: "clock.fill", color: .orange, title: "Shorter around \(hourLabel(hour))",
                    detail: "~\(wait) min then — saves about \(saves) min")
        }
    }

    private func tipRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "Now · 45 min" normally; the touched hour while dragging across the chart.
    private var selectionCaption: some View {
        let hour = selectedHour ?? currentHour
        let wait = profile[hour]
        let label = hour == currentHour ? "Now" : hourLabel(hour)
        return HStack(spacing: 4) {
            Text(label).fontWeight(.semibold)
            if let wait { Text("· ~\(wait) min") }
            Spacer()
            if selectedHour == nil {
                Text("Touch the chart to see any hour")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Chart

    @ViewBuilder
    private func waitChart(_ bars: [WaitForecast.Bar]) -> some View {
        let best = bars.filter { $0.hour > currentHour }.min { $0.wait < $1.wait }
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Hour", bar.hour),
                    y: .value("Wait", bar.wait),
                    width: .ratio(0.7)
                )
                .cornerRadius(3)
                .foregroundStyle(barColor(bar))
                .opacity(opacity(for: bar))
                .annotation(position: .top, spacing: 2) {
                    if bar.hour == currentHour {
                        Text("Now")
                            .font(.system(size: chartLabelSize + 1, weight: .bold))
                            .foregroundStyle(.primary)
                    } else if bar.hour == best?.hour, selectedHour == nil {
                        Image(systemName: "star.fill")
                            .font(.system(size: chartLabelSize + 1))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .chartXScale(domain: (bars.first?.hour ?? 9) - 1 ... (bars.last?.hour ?? 21) + 1)
        .chartXSelection(value: $selectedHour)
        .chartXAxis {
            AxisMarks(values: axisHours(bars)) { value in
                AxisValueLabel {
                    if let h = value.as(Int.self) { Text(hourLabel(h)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text("\(m)") }
                }
            }
        }
        .accessibilityLabel("Expected wait by hour")
        .accessibilityValue(bars.map { "\(hourLabel($0.hour)) \($0.wait) minutes" }.joined(separator: ", "))
    }

    private func barColor(_ bar: WaitForecast.Bar) -> Color {
        waitTimeColor(minutes: bar.wait, isOperating: true, status: "OPERATING")
    }

    /// Past hours fade; the touched hour (or now) stands out.
    private func opacity(for bar: WaitForecast.Bar) -> Double {
        if let selectedHour { return bar.hour == selectedHour ? 1 : 0.35 }
        return bar.hour < currentHour ? 0.3 : 1
    }

    /// Every 3 hours across the open day.
    private func axisHours(_ bars: [WaitForecast.Bar]) -> [Int] {
        guard let first = bars.first?.hour, let last = bars.last?.hour else { return [] }
        return Array(stride(from: first, through: last, by: 3))
    }

    /// Your own visits beat the community history, which beats the park-wide estimate.
    @ViewBuilder
    private func sourceLabel(_ source: PredictionDataSource) -> some View {
        if case .personalHistory = source {
            dataSourceLabel(source)
        } else if !community.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "person.3.fill").font(.caption2)
                Text("Typical \(Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: .now) - 1])")
                    .font(.caption2)
            }
            .foregroundStyle(.blue.opacity(0.8))
        } else {
            dataSourceLabel(source)
        }
    }

    @ViewBuilder
    private func dataSourceLabel(_ source: PredictionDataSource) -> some View {
        switch source {
        case .personalHistory(let count):
            HStack(spacing: 4) {
                Image(systemName: "person.fill").font(.caption2)
                Text("From your visits")
                    .font(.caption2)
            }
            .foregroundStyle(.blue.opacity(0.7))
        case .communityBaseline:
            HStack(spacing: 4) {
                Image(systemName: "person.3").font(.caption2)
                Text("Estimated")
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
                        .font(.system(size: chartLabelSize))
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
