import SwiftUI

// MARK: - Park Hours Header Strip

/// Compact one-line hours display for the currently visible park.
/// Shown above the park chips in WaitTimesView.
struct ParkHoursHeaderView: View {
    let park: ParkEntity
    let schedule: [ParkScheduleDay]
    let theme: ParkTheme

    @State private var showSheet = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Today's operating hours (non-extra, non-ticketed)
    private var operating: ParkScheduleDay? {
        schedule.first { $0.type == "OPERATING" || $0.type == nil }
    }

    /// Extra hours (early entry / after hours) for today
    private var extraHours: [ParkScheduleDay] {
        schedule.filter { $0.type == "EXTRA_HOURS" || $0.type == "TICKETED_EVENT" }
    }

    private func hoursText(_ day: ParkScheduleDay) -> String {
        let open  = day.openingDate.map  { Self.timeFmt.string(from: $0) } ?? "?"
        let close = day.closingDate.map  { Self.timeFmt.string(from: $0) } ?? "?"
        return "\(open) – \(close)"
    }

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let op = operating {
                    Text(hoursText(op))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                } else {
                    Text("Hours unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(extraHours) { extra in
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(hoursText(extra))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.accentColor)
                    Text(extra.isExtraHours ? "Early/Late Entry" : "Ticketed Event")
                        .font(.caption2)
                        .foregroundStyle(theme.accentColor.opacity(0.8))
                }

                Spacer()
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            ParkHoursSheet(park: park, schedule: schedule, theme: theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - 14-Day Schedule Sheet

struct ParkHoursSheet: View {
    let park: ParkEntity
    let schedule: [ParkScheduleDay]
    let theme: ParkTheme

    @Environment(\.dismiss) private var dismiss

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Group schedule by date string, show only next 14 days
    private var groupedDays: [(date: String, days: [ParkScheduleDay])] {
        let today = Calendar.current.startOfDay(for: .now)
        let cutoff = Calendar.current.date(byAdding: .day, value: 14, to: today)!

        // Parse only days within window
        var byDate: [String: [ParkScheduleDay]] = [:]
        for day in schedule {
            guard let open = day.openingDate, open >= today, open <= cutoff else { continue }
            byDate[day.date, default: []].append(day)
        }
        return byDate.keys.sorted().map { key in (date: key, days: byDate[key]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedDays, id: \.date) { group in
                    Section(headerDate(group.date)) {
                        ForEach(group.days) { day in
                            HStack {
                                Label(typeLabel(day), systemImage: typeIcon(day))
                                    .font(.subheadline)
                                    .foregroundStyle(typeColor(day, theme: theme))
                                Spacer()
                                Text(hoursText(day))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }
                if groupedDays.isEmpty {
                    ContentUnavailableView(
                        "No schedule data",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Schedule data is not yet available for this park.")
                    )
                }
            }
            .navigationTitle(park.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func headerDate(_ dateStr: String) -> String {
        // Parse the date string "YYYY-MM-DD"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: String(dateStr.prefix(10))) else { return dateStr }

        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return Self.dateFmt.string(from: d)
    }

    private func hoursText(_ day: ParkScheduleDay) -> String {
        let open  = day.openingDate.map  { Self.timeFmt.string(from: $0) } ?? "–"
        let close = day.closingDate.map  { Self.timeFmt.string(from: $0) } ?? "–"
        return "\(open) – \(close)"
    }

    private func typeLabel(_ day: ParkScheduleDay) -> String {
        switch day.type {
        case "EXTRA_HOURS":    return "Early/Late Entry"
        case "TICKETED_EVENT": return "Ticketed Event"
        default:               return "Park Hours"
        }
    }

    private func typeIcon(_ day: ParkScheduleDay) -> String {
        switch day.type {
        case "EXTRA_HOURS":    return "star.fill"
        case "TICKETED_EVENT": return "ticket.fill"
        default:               return "clock.fill"
        }
    }

    private func typeColor(_ day: ParkScheduleDay, theme: ParkTheme) -> Color {
        switch day.type {
        case "EXTRA_HOURS", "TICKETED_EVENT": return theme.accentColor
        default: return .primary
        }
    }
}
