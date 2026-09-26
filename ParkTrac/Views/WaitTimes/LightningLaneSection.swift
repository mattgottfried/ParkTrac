import SwiftUI
import SwiftData

/// Ride detail: next Lightning Lane returns + a notify-only watch for a return window.
struct LightningLaneSection: View {
    let ride: DisplayRide
    var parkName: String = ""
    /// Names differ by resort: Lightning Lane Multi/Single Pass in Orlando,
    /// Priority Pass / Premier Access at Tokyo Disney Resort.
    var resort: ParkGroup = .disney

    private var names: (free: String, paid: String, section: String, short: String) { resort.returnPassNames }
    private var bookingApp: BookingApp { .for(resort) }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PlanItem> { $0.kind == "ll" && !$0.isDone }) private var openLLReturns: [PlanItem]

    private var service: LightningLaneWatchService { .shared }
    private var existing: LightningLaneWatch? { service.watch(for: ride.id) }

    @State private var windowStart: Date = LightningLaneSection.defaultStart()
    @State private var windowEnd: Date = LightningLaneSection.defaultEnd()
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(names.section, systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.yellow)

            if let multi = ride.multiPass {
                row(title: names.free, info: multi)
            }
            if let single = ride.singlePass {
                row(title: single.price.map { "\(names.paid) · \($0)" } ?? names.paid, info: single)
            }

            // Already booked → no need to keep watching
            if ride.multiPass != nil && loggedReturn == nil {
                watchControls
            }

            if let logged = loggedReturn, let start = logged.llReturnStart {
                Label("Return logged: \(windowText(start: start, end: logged.llReturnEnd))",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text("You'll get a reminder 10 minutes before it closes. Mark it done in My Day after you ride.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button {
                        bookingApp.open()
                    } label: {
                        Label("Book in \(bookingApp.shortLabel)", systemImage: "arrow.up.forward.app")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        logBooked()
                    } label: {
                        Label("I Booked It", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!(ride.multiPass?.isAvailable ?? false))
                }

                Text(bookedHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadExisting() }
    }

    // MARK: Booked

    /// Today's logged Lightning Lane for this ride that hasn't been used yet
    private var loggedReturn: PlanItem? {
        openLLReturns.first { $0.rideId == ride.id && Calendar.current.isDateInToday($0.date) }
    }

    private var bookedHint: String {
        if let start = ride.multiPass?.returnStart, ride.multiPass?.isAvailable == true {
            return "\"I Booked It\" logs the \(start.formatted(date: .omitted, time: .shortened)) return shown above. Booked a different time? Use Log Return Time below."
        }
        return "Booking happens in the \(bookingApp.appName). Use Log Return Time below to record what you booked."
    }

    private func windowText(start: Date, end: Date?) -> String {
        let s = start.formatted(date: .omitted, time: .shortened)
        guard let end, end != .distantFuture else { return s }
        return "\(s)–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private func logBooked() {
        guard let multi = ride.multiPass, multi.isAvailable, let start = multi.returnStart else { return }
        ReturnTimeLogger.logLightningLaneNow(
            rideId: ride.id, rideName: ride.name, parkName: parkName,
            returnStart: start, returnEnd: multi.returnEnd,
            resort: resort, passLabel: names.free, context: context)
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
                Text("Alert me when a \(names.free) return opens between:")
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
            rideId: ride.id, rideName: ride.name, parkId: ride.parkId, parkName: parkName,
            day: Calendar.current.startOfDay(for: .now),
            windowStart: start, windowEnd: end)
        watch.passName = names.free
        watch.resortRaw = resort.rawValue
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
