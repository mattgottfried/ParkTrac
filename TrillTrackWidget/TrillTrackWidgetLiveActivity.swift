import ActivityKit
import WidgetKit
import SwiftUI

struct TrillTrackWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThrillTrackActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(for: context.attributes))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeText(context: context, font: .body.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(bottomText(for: context.attributes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: icon(for: context.attributes))
            } compactTrailing: {
                TimeText(context: context, font: .caption2.monospacedDigit())
            } minimal: {
                Image(systemName: icon(for: context.attributes))
            }
        }
    }

    private func icon(for attributes: ThrillTrackActivityAttributes) -> String {
        switch attributes.mode {
        case .returnTime:  return "bolt.fill"
        case .waitTimer:   return "stopwatch.fill"
        case .dining:      return "fork.knife"
        case .ropeDrop:    return "sunrise.fill"
        case .nextBooking: return "clock.badge.checkmark.fill"
        }
    }

    private func bottomText(for attributes: ThrillTrackActivityAttributes) -> String {
        if attributes.subtitle.isEmpty {
            return attributes.label
        }
        return "\(attributes.label) · \(attributes.subtitle)"
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>

    /// Any mode that renders as a countdown to `countdownEnd`.
    private var isCountdown: Bool {
        switch context.attributes.mode {
        case .returnTime, .dining, .ropeDrop, .nextBooking: return true
        case .waitTimer: return false
        }
    }

    private var iconName: String {
        switch context.attributes.mode {
        case .returnTime:  return "bolt.fill"
        case .waitTimer:   return "stopwatch.fill"
        case .dining:      return "fork.knife"
        case .ropeDrop:    return "sunrise.fill"
        case .nextBooking: return "clock.badge.checkmark.fill"
        }
    }

    /// Label shown when the countdown target has passed.
    private var closedText: String {
        switch context.attributes.mode {
        case .dining:      return "Reservation time"
        case .ropeDrop:    return "Park is open"
        case .nextBooking: return "Eligible now"
        default:           return "Window closed"
        }
    }

    /// Prefix shown under the live countdown (e.g. "Return by 3:15 PM").
    private func caption(for end: Date) -> String {
        switch context.attributes.mode {
        case .dining:      return "Reservation at \(end.formatted(date: .omitted, time: .shortened))"
        case .ropeDrop:    return "Opens at \(end.formatted(date: .omitted, time: .shortened))"
        case .nextBooking: return "Eligible at \(end.formatted(date: .omitted, time: .shortened))"
        default:           return "Return by \(end.formatted(date: .omitted, time: .shortened))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(.yellow)
                Text(context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(context.attributes.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !context.attributes.subtitle.isEmpty {
                Text(context.attributes.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if isCountdown {
                if let end = context.state.countdownEnd, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.title.monospacedDigit())
                        .foregroundStyle(.white)
                    Text(caption(for: end))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                } else if context.state.countdownEnd != nil {
                    Text(closedText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Valid until park close")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            } else if let start = context.state.startedAt {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Waiting")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(start, style: .timer)
                        .font(.title.monospacedDigit())
                        .foregroundStyle(.white)
                }
                if let posted = context.state.postedMinutes, posted > 0 {
                    Text("Posted wait: \(posted) min")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding()
    }
}

private struct TimeText: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>
    let font: Font

    private var isCountdown: Bool {
        switch context.attributes.mode {
        case .returnTime, .dining, .ropeDrop, .nextBooking: return true
        case .waitTimer: return false
        }
    }

    var body: some View {
        if isCountdown, let end = context.state.countdownEnd, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true).font(font)
        } else if isCountdown {
            Image(systemName: context.state.countdownEnd == nil ? "infinity" : "checkmark")
        } else if context.attributes.mode == .waitTimer, let start = context.state.startedAt {
            Text(start, style: .timer).font(font)
        } else {
            EmptyView()
        }
    }
}
