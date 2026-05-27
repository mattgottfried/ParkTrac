import SwiftUI

// MARK: - Crowd Calendar Card (compact, shown in StatsView)

struct CrowdCalendarCard: View {
    let resort: ParkGroup

    @State private var selectedDate: Date? = nil
    @State private var showFullCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Crowd Calendar", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                NavigationLink("View All") {
                    CrowdCalendarView(resort: resort)
                }
                .font(.subheadline)
            }

            Text("Predicted crowd levels for \(resort.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Compact 3-week look-ahead grid
            MiniCalendarGrid(resort: resort, selectedDate: $selectedDate, weeks: 5)

            // Legend
            HStack(spacing: 14) {
                ForEach([CrowdLevel.ghost, .low, .moderate, .high, .veryHigh], id: \.rawValue) { level in
                    HStack(spacing: 4) {
                        Circle().fill(level.color).frame(width: 8, height: 8)
                        Text(level.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Selected day advice
            if let date = selectedDate {
                let level = CrowdCalendarService.crowdLevel(for: date, resort: resort)
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(level.color)
                    Text(CrowdCalendarService.bestTimeAdvice(for: level))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(level.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Full Crowd Calendar View

struct CrowdCalendarView: View {
    let resort: ParkGroup

    @State private var selectedDate: Date? = nil
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Month navigation
                HStack {
                    Button {
                        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(monthTitle)
                        .font(.headline)
                    Spacer()
                    Button {
                        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding(.horizontal)

                // Weekday header
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(weekdaySymbols, id: \.self) { sym in
                        Text(sym)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    // Leading blank cells
                    ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 36) }

                    // Day cells
                    ForEach(daysInMonth, id: \.self) { date in
                        DayCell(date: date, resort: resort, isSelected: selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false)
                            .onTapGesture { selectedDate = date }
                    }
                }
                .padding(.horizontal, 8)

                // Selected day detail
                if let date = selectedDate {
                    let level = CrowdCalendarService.crowdLevel(for: date, resort: resort)
                    VStack(spacing: 8) {
                        HStack {
                            Text(dateLabel(date))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(level.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(level.color)
                        }
                        Text(CrowdCalendarService.bestTimeAdvice(for: level))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(level.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Legend
                HStack(spacing: 16) {
                    ForEach([CrowdLevel.ghost, .low, .moderate, .high, .veryHigh], id: \.rawValue) { level in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(level.color).frame(width: 12, height: 12)
                            Text(level.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom)
            }
            .padding(.top)
        }
        .navigationTitle("Crowd Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private var daysInMonth: [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        return range.compactMap { day -> Date? in
            cal.date(bySetting: .day, value: day, of: displayedMonth)
        }
    }

    private var leadingBlanks: Int {
        let cal = Calendar.current
        let firstDay = Calendar.current.startOfMonth(for: displayedMonth)
        return (cal.component(.weekday, from: firstDay) - 1 + 7) % 7
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Mini Calendar Grid (compact, for card)

struct MiniCalendarGrid: View {
    let resort: ParkGroup
    @Binding var selectedDate: Date?
    var weeks: Int = 5

    private var dates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Start from the Sunday of the current week
        let weekdayOffset = (cal.component(.weekday, from: today) - 1 + 7) % 7
        guard let startSunday = cal.date(byAdding: .day, value: -weekdayOffset, to: today) else { return [] }
        return (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: startSunday) }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(dates, id: \.self) { date in
                DayCell(
                    date: date,
                    resort: resort,
                    isSelected: selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                )
                .onTapGesture { selectedDate = date }
            }
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let resort: ParkGroup
    let isSelected: Bool

    private var level: CrowdLevel { CrowdCalendarService.crowdLevel(for: date, resort: resort) }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: .now) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isPast ? level.color.opacity(0.2) : level.color.opacity(0.7))

            if isToday {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white, lineWidth: 2)
            }

            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.primary, lineWidth: 2)
            }

            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isPast ? .secondary : .white)
        }
        .frame(height: 30)
    }
}

// MARK: - Calendar extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
