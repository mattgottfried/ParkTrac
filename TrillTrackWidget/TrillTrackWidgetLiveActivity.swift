import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Style per activity type

/// Icon, accent color and tap target for each kind of activity. The tap targets mirror
/// `DeepLink` in the app target (ParkTrac/Services/DeepLinkRouter.swift), which the widget
/// doesn't compile.
private struct ActivityStyle {
    let icon: String
    let color: Color
    let url: URL?

    init(_ attributes: ThrillTrackActivityAttributes) {
        switch attributes.mode {
        case .returnTime:
            let accessPass = ["DAS", "AAP"].contains(attributes.label)
            icon = accessPass ? "figure.roll" : "bolt.fill"
            color = accessPass ? .teal : .yellow
            url = URL(string: "thrilltrack://plan")
        case .waitTimer:
            icon = "stopwatch.fill"
            color = .cyan
            url = URL(string: "thrilltrack://timer")
        case .dining:
            icon = "fork.knife"
            color = .orange
            url = URL(string: "thrilltrack://dining")
        case .ropeDrop:
            icon = "sunrise.fill"
            color = .pink
            url = URL(string: "thrilltrack://waittimes")
        case .nextBooking:
            icon = "clock.badge.checkmark.fill"
            color = .mint
            url = URL(string: "thrilltrack://plan")
        case .parkDay:
            icon = "sparkles"
            color = .indigo
            url = URL(string: "thrilltrack://plan")
        }
    }
}

/// Same thresholds as the app's `waitTimeColor` (WaitTimeColor.swift)
private func waitColor(_ minutes: Int) -> Color {
    if minutes < 30 { return .green }
    if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
    return .red
}

private func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

// MARK: - Widget

struct TrillTrackWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThrillTrackActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(ActivityStyle(context.attributes).url)
        } dynamicIsland: { context in
            let style = ActivityStyle(context.attributes)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.attributes.mode == .parkDay, let wait = context.state.stopWait {
                        WaitBadge(wait: wait, size: 44)
                    } else {
                        Image(systemName: style.icon)
                            .font(.title2)
                            .foregroundStyle(style.color)
                            .frame(width: 44, height: 44)
                            .background(style.color.opacity(0.2), in: Circle())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingTime(context: context, font: .title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(style.color)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.mode == .parkDay
                             ? (context.state.stopTitle ?? context.attributes.title)
                             : context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(centerCaption(context))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomDetail(context: context, color: style.color)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                if context.attributes.mode == .parkDay, let wait = context.state.stopWait {
                    Text("\(wait)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(waitColor(wait))
                } else {
                    Image(systemName: style.icon).foregroundStyle(style.color)
                }
            } compactTrailing: {
                if context.attributes.mode == .parkDay {
                    Image(systemName: "sparkles").foregroundStyle(style.color)
                } else {
                    TrailingTime(context: context, font: .caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(style.color)
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: style.icon).foregroundStyle(style.color)
            }
            .widgetURL(style.url)
            .keylineTint(style.color)
        }
    }

    private func centerCaption(_ context: ActivityViewContext<ThrillTrackActivityAttributes>) -> String {
        let a = context.attributes
        switch a.mode {
        case .parkDay:
            return context.state.stopDetail ?? a.title
        default:
            return a.subtitle.isEmpty ? a.label : "\(a.label) · \(a.subtitle)"
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>

    private var style: ActivityStyle { ActivityStyle(context.attributes) }

    var body: some View {
        Group {
            if context.attributes.mode == .parkDay {
                ParkDayView(context: context, color: style.color)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    BottomDetail(context: context, color: style.color)
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: style.icon)
                .font(.headline)
                .foregroundStyle(style.color)
                .frame(width: 34, height: 34)
                .background(style.color.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !context.attributes.subtitle.isEmpty {
                    Text(context.attributes.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(context.attributes.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(style.color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(style.color.opacity(0.18), in: Capsule())
        }
    }
}

/// The countdown / stopwatch / window body shared by the Lock Screen and expanded island.
private struct BottomDetail: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let color: Color

    private var a: ThrillTrackActivityAttributes { context.attributes }
    private var s: ThrillTrackActivityAttributes.ContentState { context.state }
    private var isAccessPass: Bool { a.mode == .returnTime && ["DAS", "AAP"].contains(a.label) }

    var body: some View {
        switch a.mode {
        case .parkDay:
            VStack(alignment: .leading, spacing: 2) {
                if let then = s.thenText { Text(then).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                if let rain = s.rainText {
                    Label(rain, systemImage: "cloud.rain.fill").font(.caption2).foregroundStyle(.cyan).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .waitTimer:
            waitTimer
        case .returnTime where !isAccessPass && s.windowStart != nil && s.countdownEnd != nil:
            returnWindow
        default:
            countdown
        }
    }

    /// Timed pass: a bar across the return window, and when it closes.
    @ViewBuilder
    private var returnWindow: some View {
        if let start = s.windowStart, let end = s.countdownEnd {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if end > .now {
                        Text(start > .now ? "Opens \(timeText(start))" : "Window open · closes in")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer(minLength: 4)
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(color)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120, alignment: .trailing)
                    } else {
                        Text("Window closed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                if start < end {
                    ProgressView(timerInterval: start...end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(color)
                }
                Text("\(timeText(start)) – \(timeText(end))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    /// Stopwatch against the posted wait: the bar fills toward the posted time.
    @ViewBuilder
    private var waitTimer: some View {
        if let start = s.startedAt {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("In line")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer(minLength: 4)
                    Text(start, style: .timer)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
                if let posted = s.postedMinutes, posted > 0 {
                    ProgressView(timerInterval: start...start.addingTimeInterval(Double(posted) * 60),
                                 countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(color)
                    Text("Posted wait \(posted) min")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    /// Countdown to a time (dining, rope drop, next booking, DAS/AAP return).
    @ViewBuilder
    private var countdown: some View {
        if let end = s.countdownEnd, end > .now {
            HStack(alignment: .firstTextBaseline) {
                Text(caption(end))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 4)
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
        } else if s.countdownEnd != nil {
            Label(doneText, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        } else {
            Label("Valid until park close", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func caption(_ end: Date) -> String {
        if isAccessPass { return "Return at \(timeText(end))" }
        switch a.mode {
        case .dining: return "Reservation \(timeText(end))"
        case .ropeDrop: return "Opens \(timeText(end))"
        case .nextBooking: return "Eligible \(timeText(end))"
        default: return "Return by \(timeText(end))"
        }
    }

    private var doneText: String {
        if isAccessPass { return "Ready — ride any time" }
        switch a.mode {
        case .dining: return "Reservation time"
        case .ropeDrop: return "Park is open"
        case .nextBooking: return "Eligible now"
        default: return "Window closed"
        }
    }
}

/// Park Day on the Lock Screen: the Next Up stop with its wait tile.
private struct ParkDayView: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let color: Color

    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("NEXT UP · \(context.attributes.title)", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let progress = s.progressText {
                    Text(progress)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if let wait = s.stopWait {
                    WaitBadge(wait: wait, size: 56)
                } else {
                    Image(systemName: "theatermasks.fill")
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(width: 56, height: 56)
                        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.stopTitle ?? "")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let detail = s.stopDetail {
                        Text(detail).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    if let then = s.thenText {
                        Text(then).font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    if let rain = s.rainText {
                        Label(rain, systemImage: "cloud.rain.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Colored wait square (matches the app's ride cards)
private struct WaitBadge: View {
    let wait: Int
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text("\(wait)")
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text("min").font(.system(size: size * 0.18, weight: .semibold))
        }
        .lineLimit(1)
        .foregroundStyle(waitColor(wait))
        .frame(width: size, height: size)
        .background(waitColor(wait).opacity(0.2), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// The ticking time in the island's trailing spots.
private struct TrailingTime: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let font: Font

    var body: some View {
        let s = context.state
        switch context.attributes.mode {
        case .waitTimer:
            if let start = s.startedAt {
                Text(start, style: .timer).font(font).multilineTextAlignment(.trailing)
            }
        case .parkDay:
            if let wait = s.stopWait {
                Text("\(wait) min").font(font)
            }
        default:
            if let end = s.countdownEnd, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true).font(font).multilineTextAlignment(.trailing)
            } else {
                Image(systemName: s.countdownEnd == nil ? "infinity" : "checkmark")
            }
        }
    }
}
