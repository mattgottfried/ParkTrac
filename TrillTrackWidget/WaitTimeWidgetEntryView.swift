import WidgetKit
import SwiftUI

struct WaitTimeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaitTimeWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.resortName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
            if let level = entry.crowdLevel {
                Label(level.rawValue, systemImage: level.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            if let top = entry.topRides.first {
                Text(top.name)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(top.wait) min wait")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("No live data").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(entry.theme.primaryColor.gradient, for: .widget)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.resortName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let level = entry.crowdLevel {
                    Label(level.rawValue, systemImage: level.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            if entry.topRides.isEmpty {
                Text("No live data").font(.caption).foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(entry.topRides.prefix(3), id: \.name) { ride in
                    HStack {
                        Text(ride.name)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(ride.wait) min")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(entry.theme.primaryColor.gradient, for: .widget)
    }
}

struct WaitTimeWidget: Widget {
    let kind = "WaitTimeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WaitTimeWidgetConfigIntent.self, provider: WaitTimeTimelineProvider()) { entry in
            WaitTimeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Wait Times")
        .description("Live wait times for your chosen resort.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
