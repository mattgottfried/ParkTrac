import SwiftUI
import SwiftData

/// One day-by-day view of a whole trip — which resort has a plan each day, how many My Day
/// items and dining reservations, instead of piecing it together from My Day's Coming Up list.
/// Reuses `FutureDayView` as the tap-through, so items/dining/delete all already work there.
struct VacationCalendarView: View {
    let trip: Trip

    @Environment(AppState.self) private var appState
    @Query(sort: \PlanItem.sortOrder) private var allItems: [PlanItem]
    @Query private var allDining: [DiningReservation]

    private var days: [Date] { VacationCalendar.days(start: trip.startDate, end: trip.endDate) }

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(trip.resorts, id: \.self) { resort in
                        NavigationLink {
                            FutureDayView(day: day, resort: resort.rawValue)
                        } label: {
                            dayRow(day: day, resort: resort)
                        }
                    }
                }
            }
        }
        .navigationTitle("Vacation Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func itemCount(day: Date, resort: ParkGroup) -> Int {
        allItems.filter { $0.resort == resort.rawValue && Calendar.current.isDate($0.date, inSameDayAs: day)
            && !UndoDeleteCenter.shared.isHidden($0) }.count
    }

    private func diningCount(day: Date, resort: ParkGroup) -> Int {
        allDining.filter { $0.resort == resort.rawValue && Calendar.current.isDate($0.date, inSameDayAs: day) }.count
    }

    /// True when your annual pass tier for that resort's brand blocks this day out.
    private func isBlockedOut(day: Date, resort: ParkGroup) -> Bool {
        switch resort.brand {
        case .disney:    return BlockOutService.isBlockedOut(day, disney: appState.disneyPassTier)
        case .universal: return BlockOutService.isBlockedOut(day, universal: appState.universalPassTier)
        }
    }

    private var hasSavedPlan: (Date, ParkGroup) -> Bool {
        { day, resort in
            ItineraryService.shared.upcoming.contains {
                $0.resortRaw == resort.rawValue && Calendar.current.isDate($0.day, inSameDayAs: day)
            }
        }
    }

    private func dayRow(day: Date, resort: ParkGroup) -> some View {
        let items = itemCount(day: day, resort: resort)
        let dining = diningCount(day: day, resort: resort)
        let saved = hasSavedPlan(day, resort)
        let blocked = isBlockedOut(day: day, resort: resort)
        return HStack {
            Label(resort.shortName, systemImage: resort.brand == .disney ? "sparkles" : "star.fill")
                .font(.subheadline.weight(.medium))
            Spacer()
            if blocked {
                Label("Blocked Out", systemImage: "nosign")
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
            if items == 0 && dining == 0 && !saved {
                if !blocked { Text("Nothing planned").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack(spacing: 10) {
                    if saved {
                        Label("Plan", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                    }
                    if items > 0 {
                        Label("\(items)", systemImage: "ticket.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    if dining > 0 {
                        Label("\(dining)", systemImage: "fork.knife").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
