import SwiftUI

/// Ride detail: next Lightning Lane returns + a notify-only watch for a return window.
struct LightningLaneSection: View {
    let ride: DisplayRide

    private var service: LightningLaneWatchService { .shared }
    private var existing: LightningLaneWatch? { service.watch(for: ride.id) }

    @State private var windowStart: Date = LightningLaneSection.defaultStart()
    @State private var windowEnd: Date = LightningLaneSection.defaultEnd()
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Lightning Lane", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.yellow)

            if let multi = ride.multiPass {
                row(title: "Multi Pass", info: multi)
            }
            if let single = ride.singlePass {
                row(title: single.price.map { "Single Pass · \($0)" } ?? "Single Pass", info: single)
            }

            if ride.multiPass != nil {
                watchControls
            }

            Button {
                BookingApp.disney.open()
            } label: {
                Label("Book in the Disney App", systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("ThrillTrack only alerts you — booking happens in Disney's app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { loadExisting() }
    }

    // MARK: Rows

    private func row(title: String, info: LightningLaneInfo) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(detail(for: info))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(info.isAvailable ? Color.primary : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(for info: LightningLaneInfo) -> String {
        switch info.state {
        case .available:
            guard let start = info.returnStart else { return "Available" }
            return "Next return \(start.formatted(date: .omitted, time: .shortened))"
        case .temporarilyFull: return "Full for now"
        case .soldOut:         return "Sold out"
        case .unknown:         return "—"
        }
    }

    // MARK: Watch

    @ViewBuilder
    private var watchControls: some View {
        if let watch = existing, !editing {
            VStack(alignment: .leading, spacing: 8) {
                Label("Watching \(watch.windowText)", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                if let last = watch.lastNotifiedStart {
                    Text("Alerted for \(last.formatted(date: .omitted, time: .shortened)) — you'll hear again only if an earlier return opens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Change Window") { editing = true }
                    Spacer()
                    Button("Stop Watching", role: .destructive) { service.remove(rideId: ride.id) }
                }
                .font(.subheadline)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alert me when a Multi Pass return opens between:")
                    .font(.subheadline)
                DatePicker("Earliest", selection: $windowStart, displayedComponents: .hourAndMinute)
                DatePicker("Latest", selection: $windowEnd, in: windowStart..., displayedComponents: .hourAndMinute)
                Button {
                    saveWatch()
                } label: {
                    Label(existing == nil ? "Watch for Openings" : "Update Window", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                Text("Checks every minute while ThrillTrack is open, and about hourly in the background when iOS allows.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadExisting() {
        guard let watch = existing else { return }
        windowStart = watch.windowStart
        windowEnd = watch.windowEnd
    }

    private func saveWatch() {
        // DatePicker only edits the time; pin both ends to today
        let start = Self.today(at: windowStart)
        let end = max(start, Self.today(at: windowEnd))
        var watch = existing ?? LightningLaneWatch(
            rideId: ride.id, rideName: ride.name, parkId: ride.parkId,
            day: Calendar.current.startOfDay(for: .now),
            windowStart: start, windowEnd: end)
        watch.windowStart = start
        watch.windowEnd = end
        service.save(watch)
        editing = false
        Task { await NotificationService.shared.requestAuthorization() }
    }

    // MARK: Time helpers

    private static func today(at time: Date) -> Date {
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: .now) ?? time
    }

    /// Now, rounded up to the next quarter hour
    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let now = Date()
        let minute = cal.component(.minute, from: now)
        let add = (15 - minute % 15) % 15
        return cal.date(byAdding: .minute, value: add, to: now) ?? now
    }

    /// 9 PM today, or the start + 1 h if it's already later than that
    private static func defaultEnd() -> Date {
        let nine = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
        return max(nine, defaultStart().addingTimeInterval(3600))
    }
}
