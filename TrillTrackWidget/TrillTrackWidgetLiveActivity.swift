import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Colors

/// Background and accent from the resort (`ThrillTrackActivityAttributes.resortRaw`, the app's
/// `ParkGroup.rawValue`). Unknown / missing → plain black with a white accent.
private struct ResortPalette {
    let top: Color
    let bottom: Color
    let accent: Color

    init(_ resortRaw: String?) {
        switch resortRaw {
        case "Walt Disney World":
            top = Color(red: 0.05, green: 0.10, blue: 0.30)
            bottom = Color(red: 0.10, green: 0.27, blue: 0.62)
            accent = Color(red: 1.0, green: 0.82, blue: 0.35)
        case "Universal Orlando":
            top = Color(red: 0.09, green: 0.10, blue: 0.12)
            bottom = Color(red: 0.02, green: 0.33, blue: 0.36)
            accent = Color(red: 0.72, green: 0.95, blue: 0.30)
        case "Tokyo Disney Resort":
            top = Color(red: 0.08, green: 0.08, blue: 0.28)
            bottom = Color(red: 0.55, green: 0.18, blue: 0.40)
            accent = Color(red: 1.0, green: 0.66, blue: 0.82)
        case "Universal Studios Japan":
            top = Color(red: 0.06, green: 0.05, blue: 0.06)
            bottom = Color(red: 0.50, green: 0.06, blue: 0.10)
            accent = Color(red: 1.0, green: 0.75, blue: 0.25)
        default:
            top = .black
            bottom = Color(white: 0.12)
            accent = .white
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Glyph and tap target per activity type. The tap targets mirror `DeepLink` in the app
/// (ParkTrac/Services/DeepLinkRouter.swift), which the widget doesn't compile.
private struct ActivityKind {
    let glyph: String
    let url: URL?

    init(_ attributes: ThrillTrackActivityAttributes) {
        switch attributes.mode {
        case .returnTime:
            glyph = ["DAS", "AAP"].contains(attributes.label) ? "figure.roll" : "bolt.fill"
            url = URL(string: "thrilltrack://plan")
        case .waitTimer:
            glyph = "stopwatch.fill"
            url = URL(string: "thrilltrack://timer")
        case .dining:
            glyph = "fork.knife"
            url = URL(string: "thrilltrack://dining")
        case .ropeDrop:
            glyph = "sunrise.fill"
            url = URL(string: "thrilltrack://waittimes")
        case .nextBooking:
            glyph = "clock.badge.checkmark.fill"
            url = URL(string: "thrilltrack://plan")
        case .parkDay:
            glyph = "sparkles"
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

private func isAccessPass(_ a: ThrillTrackActivityAttributes) -> Bool {
    a.mode == .returnTime && ["DAS", "AAP"].contains(a.label)
}

// MARK: - Widget

struct TrillTrackWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThrillTrackActivityAttributes.self) { context in
            let palette = ResortPalette(context.attributes.resortRaw)
            LockScreenView(context: context, palette: palette)
                .activityBackgroundTint(palette.top)
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(ActivityKind(context.attributes).url)
        } dynamicIsland: { context in
            let palette = ResortPalette(context.attributes.resortRaw)
            let kind = ActivityKind(context.attributes)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.attributes.mode == .parkDay, let wait = context.state.stopWait {
                        WaitBadge(wait: wait, size: 46)
                    } else {
                        Image(systemName: kind.glyph)
                            .font(.title3)
                            .foregroundStyle(palette.accent)
                            .frame(width: 46, height: 46)
                            .background(palette.accent.opacity(0.18), in: Circle())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.attributes.mode != .parkDay {
                        BigTime(context: context, size: 26)
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: 110, alignment: .trailing)
                    } else if let progress = context.state.progressText {
                        Text(progress)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.mode == .parkDay
                             ? (context.state.stopTitle ?? context.attributes.title)
                             : context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(ActivityText.caption(context))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if context.attributes.mode == .parkDay {
                            ThenRow(stops: Array((context.state.upcoming ?? []).dropFirst()))
                        } else {
                            ProgressBar(context: context, tint: palette.accent)
                        }
                        ActionButtons(context: context, tint: palette.accent)
                    }
                }
            } compactLeading: {
                if context.attributes.mode == .parkDay, let wait = context.state.stopWait {
                    Text("\(wait)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(waitColor(wait))
                } else {
                    Image(systemName: kind.glyph).foregroundStyle(palette.accent)
                }
            } compactTrailing: {
                if context.attributes.mode == .parkDay {
                    Image(systemName: "sparkles").foregroundStyle(palette.accent)
                } else {
                    BigTime(context: context, size: 13)
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: kind.glyph).foregroundStyle(palette.accent)
            }
            .widgetURL(kind.url)
            .keylineTint(palette.accent)
        }
    }
}

// MARK: - Text

private enum ActivityText {
    /// One line under the big number
    static func caption(_ context: ActivityViewContext<ThrillTrackActivityAttributes>) -> String {
        let a = context.attributes
        let s = context.state
        switch a.mode {
        case .parkDay:
            return s.stopDetail ?? a.title
        case .waitTimer:
            if let posted = s.postedMinutes, posted > 0 { return "in line · posted \(posted) min" }
            return "in line"
        case .returnTime:
            if isAccessPass(a) {
                guard let end = s.countdownEnd else { return "valid until park close" }
                return end > .now ? "until you can return · \(timeText(end))" : "ride any time"
            }
            guard let end = s.countdownEnd else { return a.label }
            if let start = s.windowStart, start > .now {
                return "until your window closes · opens \(timeText(start))"
            }
            return end > .now ? "until your window closes · \(timeText(end))" : "window closed"
        case .dining:
            return s.countdownEnd.map { $0 > .now ? "until your reservation · \(timeText($0))" : "reservation time" } ?? ""
        case .ropeDrop:
            return s.countdownEnd.map { $0 > .now ? "until the park opens · \(timeText($0))" : "the park is open" } ?? ""
        case .nextBooking:
            return s.countdownEnd.map { $0 > .now ? "until you can book again · \(timeText($0))" : "you can book now" } ?? ""
        }
    }

    /// Big text once a countdown has run out
    static func done(_ a: ThrillTrackActivityAttributes) -> String {
        if isAccessPass(a) { return "Ready" }
        switch a.mode {
        case .dining: return "Now"
        case .ropeDrop: return "Open!"
        case .nextBooking: return "Book now"
        default: return "Closed"
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let palette: ResortPalette

    var body: some View {
        Group {
            if context.attributes.mode == .parkDay {
                ParkDayTimeline(context: context, palette: palette)
            } else {
                BigNumberView(context: context, palette: palette)
            }
        }
        .padding(16)
        .background(palette.gradient)
    }
}

/// Scoreboard style: small caps line, a huge number, one caption, a bar and the button.
private struct BigNumberView: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let palette: ResortPalette

    var body: some View {
        let a = context.attributes
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: ActivityKind(a).glyph)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.accent)
                Text("\(a.title) · \(a.label)".uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            BigTime(context: context, size: 46)
                .foregroundStyle(palette.accent)
            Text(ActivityText.caption(context))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            ProgressBar(context: context, tint: palette.accent)
            ActionButtons(context: context, tint: palette.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Park Day: the next three stops on a line, the next one filled in.
private struct ParkDayTimeline: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let palette: ResortPalette

    var body: some View {
        let s = context.state
        let stops = s.upcoming ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.attributes.title, systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let progress = s.progressText {
                    Text(progress)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if stops.isEmpty {
                // Older payload without the timeline
                Text(s.stopTitle ?? "").font(.headline).foregroundStyle(.white)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                        TimelineColumn(stop: stop, isNext: index == 0, isLast: index == stops.count - 1,
                                       accent: palette.accent)
                    }
                }
            }

            if let detail = s.stopDetail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            if let rain = s.rainText {
                Label(rain, systemImage: "cloud.rain.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }
            ActionButtons(context: context, tint: palette.accent)
        }
    }
}

private struct TimelineColumn: View {
    let stop: ThrillTrackActivityAttributes.UpcomingStop
    let isNext: Bool
    let isLast: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Circle()
                    .fill(isNext ? accent : Color.clear)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(isLast ? Color.clear : accent.opacity(0.5))
                    .frame(height: 2)
            }
            Text(timeText(stop.time))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(isNext ? 1 : 0.7))
            Text(stop.title)
                .font(isNext ? .caption.weight(.bold) : .caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let wait = stop.wait {
                Text("\(wait) min")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(waitColor(wait))
            } else {
                Image(systemName: stop.kind == "dining" ? "fork.knife"
                      : stop.kind == "show" ? "theatermasks.fill" : "cup.and.saucer.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 6)
    }
}

/// "Then: Peter Pan 2:55 · Fireworks 3:40" in the expanded island
private struct ThenRow: View {
    let stops: [ThrillTrackActivityAttributes.UpcomingStop]

    var body: some View {
        if !stops.isEmpty {
            Text("Then: " + stops.map { "\($0.title) \(timeText($0.time))" }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Pieces

/// The ticking number: countdown, stopwatch, or the wait for Park Day
private struct BigTime: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let size: CGFloat

    private var font: Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }

    var body: some View {
        let s = context.state
        switch context.attributes.mode {
        case .waitTimer:
            if let start = s.startedAt {
                Text(start, style: .timer).font(font).multilineTextAlignment(.leading)
            }
        case .parkDay:
            if let wait = s.stopWait { Text("\(wait) min").font(font) }
        default:
            if let end = s.countdownEnd, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true).font(font)
            } else if s.countdownEnd == nil {
                Image(systemName: "infinity").font(.system(size: size * 0.8, weight: .bold))
            } else {
                Text(ActivityText.done(context.attributes)).font(font)
            }
        }
    }
}

/// Timed returns fill across their window; the stopwatch fills toward the posted wait.
private struct ProgressBar: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let tint: Color

    var body: some View {
        let s = context.state
        let a = context.attributes
        if a.mode == .returnTime, !isAccessPass(a), let start = s.windowStart, let end = s.countdownEnd,
           end > start, end > Date.now {
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(tint)
        } else if a.mode == .waitTimer, let start = s.startedAt, let posted = s.postedMinutes, posted > 0 {
            ProgressView(timerInterval: start...start.addingTimeInterval(Double(posted) * 60), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(tint)
        }
    }
}

/// Buttons that act without opening the app (iOS 17 `LiveActivityIntent`s, run by the app)
private struct ActionButtons: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let tint: Color

    var body: some View {
        let a = context.attributes
        let s = context.state
        switch a.mode {
        case .parkDay:
            if let rideId = s.stopRideId {
                HStack(spacing: 8) {
                    Button(intent: ParkDayDoneIntent(rideId: rideId)) {
                        Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    Button(intent: ParkDaySkipIntent(rideId: rideId)) {
                        Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity)
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(tint)
            }
        case .waitTimer:
            if s.startedAt != nil {
                Button(intent: FinishWaitTimerIntent()) {
                    Label("I'm On — Log It", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(tint)
            }
        case .returnTime:
            if let rideId = a.rideId {
                Button(intent: UsedReturnIntent(rideId: rideId)) {
                    Label("Used It", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(tint)
            }
        default:
            EmptyView()
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
