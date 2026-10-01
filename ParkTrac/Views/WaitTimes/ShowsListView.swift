import SwiftUI
import UserNotifications

struct ShowsListView: View {
    let shows: [DisplayShow]
    let theme: ParkTheme
    /// Show times in the park's time zone
    var timeZone: TimeZone = .current
    var resort: ParkGroup = .disney
    /// Park name for a show's park id
    var parkName: (String) -> String = { _ in "" }

    @State private var selected: DisplayShow?

    private var timeFmt: DateFormatter { ParkTime.formatter("h:mm a", timeZone) }

    var body: some View {
        if shows.isEmpty {
            ContentUnavailableView("No Shows", systemImage: "theatermasks",
                description: Text("No entertainment scheduled or show times unavailable."))
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(shows) { show in
                        Button {
                            selected = show
                        } label: {
                            ShowRowView(show: show, theme: theme, timeFmt: timeFmt)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows today's showtimes")
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .sheet(item: $selected) { show in
                ShowDetailSheet(show: show, parkName: parkName(show.parkId), resort: resort, timeFmt: timeFmt)
            }
        }
    }
}

/// "Missed it, catch the next one" — when the next showing is too soon to reasonably reach,
/// the showing after it (pure, unit tested).
enum ShowEncore {
    static func later(showtimes: [Date], next: Date?, now: Date = .now, leadMinutes: Int = 15) -> Date? {
        guard let next, next.timeIntervalSince(now) < Double(leadMinutes) * 60 else { return nil }
        return showtimes.filter { $0 > next }.min()
    }
}

private struct ShowRowView: View {
    let show: DisplayShow
    let theme: ParkTheme
    let timeFmt: DateFormatter

    private var nextLabel: String {
        guard let next = show.nextShowtime else { return show.statusDisplay }
        let interval = next.timeIntervalSinceNow
        if interval < 0 { return "Ended" }
        if interval < 60 { return "Starting now" }
        let mins = Int(interval / 60)
        if mins < 60 { return "In \(mins) min" }
        let hrs = mins / 60; let rem = mins % 60
        return rem == 0 ? "In \(hrs)h" : "In \(hrs)h \(rem)m"
    }

    private var nextColor: Color {
        guard let next = show.nextShowtime else { return .secondary }
        let interval = next.timeIntervalSinceNow
        if interval < 0 { return .secondary }
        if interval < 300 { return .red }
        if interval < 900 { return .orange }
        return .green
    }

    /// When the next showing is probably too soon to reach, surface the one after it — without
    /// opening the show's own sheet.
    private var laterShowtimeHint: String? {
        ShowEncore.later(showtimes: show.showtimes.compactMap(\.startDate), next: show.nextShowtime)
            .map { "Next after: \(timeFmt.string(from: $0))" }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let next = show.nextShowtime {
                    Text(timeFmt.string(from: next))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let hint = laterShowtimeHint {
                    Text(hint).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(nextLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(nextColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(nextColor.opacity(0.12), in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Show sheet

/// A show's showtimes today, a 15-minute reminder per showing, and Add to My Day.
struct ShowDetailSheet: View {
    let show: DisplayShow
    let parkName: String
    let resort: ParkGroup
    let timeFmt: DateFormatter

    @State private var remindedIds: Set<String> = []
    @State private var showAdd = false

    static let reminderLead: TimeInterval = 15 * 60

    private var times: [Date] { show.showtimes.compactMap(\.startDate).sorted() }
    private var next: Date? { show.nextShowtime }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "theatermasks.fill")
                        .font(.title)
                        .foregroundStyle(.purple)
                        .frame(width: 70, height: 70)
                        .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(show.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        if !parkName.isEmpty {
                            Text(parkName).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(next.map { "Next showing \(timeFmt.string(from: $0))" } ?? "No more showings today")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(next == nil ? Color.secondary : Color.purple)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    showAdd = true
                } label: {
                    Label("Add to My Day", systemImage: "calendar.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Today's Showtimes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    if times.isEmpty {
                        Text("Showtimes aren't published for today.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(times, id: \.self) { time in
                        showtimeRow(time)
                        if time != times.last { Divider() }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadReminders() }
        .sheet(isPresented: $showAdd) {
            AddPlanItemView(resort: resort.rawValue, prefillPark: parkName, prefillShow: show)
        }
    }

    private func showtimeRow(_ time: Date) -> some View {
        let past = time <= .now
        let isNext = time == next
        let canRemind = time.addingTimeInterval(-Self.reminderLead) > .now
        let id = reminderId(time)
        return HStack {
            Text(timeFmt.string(from: time))
                .font(.body.weight(isNext ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(past ? Color.secondary : Color.primary)
            if isNext {
                Text("Next")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.purple, in: Capsule())
            } else if past {
                Text("Ended").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if canRemind || remindedIds.contains(id) {
                Button {
                    Task { await toggleReminder(time) }
                } label: {
                    Image(systemName: remindedIds.contains(id) ? "bell.fill" : "bell")
                        .font(.body)
                        .foregroundStyle(remindedIds.contains(id) ? Color.orange : Color.secondary)
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(remindedIds.contains(id)
                                    ? "Cancel reminder for \(timeFmt.string(from: time))"
                                    : "Remind me 15 minutes before \(timeFmt.string(from: time))")
            }
        }
        .padding(.vertical, 8)
        .opacity(past ? 0.6 : 1)
    }

    // MARK: Reminders (local notification 15 min before a showing)

    private func reminderId(_ time: Date) -> String {
        "show-\(show.id)-\(Int(time.timeIntervalSince1970))"
    }

    private func loadReminders() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        remindedIds = Set(pending.map(\.identifier).filter { $0.hasPrefix("show-\(show.id)-") })
    }

    private func toggleReminder(_ time: Date) async {
        let id = reminderId(time)
        let center = UNUserNotificationCenter.current()
        if remindedIds.contains(id) {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            remindedIds.remove(id)
            return
        }
        await NotificationService.shared.requestAuthorization()
        let fire = time.addingTimeInterval(-Self.reminderLead).timeIntervalSinceNow
        guard fire > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "🎭 \(show.name) starts in 15 min"
        content.body = [timeFmt.string(from: time), parkName].filter { !$0.isEmpty }.joined(separator: " · ")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "show-\(show.id)"
        try? await center.add(UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false)))
        remindedIds.insert(id)
    }
}
