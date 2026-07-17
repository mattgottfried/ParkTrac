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
                    Text(context.attributes.rideName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.passLabel) · \(context.attributes.parkName)")
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
        attributes.mode == .returnTime ? "bolt.fill" : "stopwatch.fill"
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ThrillTrackActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: context.attributes.mode == .returnTime ? "bolt.fill" : "stopwatch.fill")
                    .foregroundStyle(.yellow)
                Text(context.attributes.rideName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(context.attributes.passLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(context.attributes.parkName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            if context.attributes.mode == .returnTime {
                if let end = context.state.returnEnd, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.title.monospacedDigit())
                        .foregroundStyle(.white)
                    Text("Return by \(end, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                } else if context.state.returnEnd != nil {
                    Text("Window closed")
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

    var body: some View {
        if context.attributes.mode == .returnTime, let end = context.state.returnEnd, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true).font(font)
        } else if context.attributes.mode == .returnTime {
            Image(systemName: context.state.returnEnd == nil ? "infinity" : "checkmark")
        } else if context.attributes.mode == .waitTimer, let start = context.state.startedAt {
            Text(start, style: .timer).font(font)
        } else {
            EmptyView()
        }
    }
}
