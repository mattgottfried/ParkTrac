import SwiftUI
import SwiftData

/// Genie-style Tip Board: your Must-Dos and plan picks with the wait now, what it usually is
/// at this time, and the best time left today.
struct TipBoardView: View {
    @Environment(AppState.self) private var appState
    @Environment(WaitTimesViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [TipBoard.Row] = []

    private var goodNow: [TipBoard.Row] { rows.filter(\.isGoodNow) }
    private var others: [TipBoard.Row] { rows.filter { !$0.isGoodNow } }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("No Picks Yet", systemImage: "star")
                    } description: {
                        Text("Star rides as Must-Do, or start a plan in the Smart Planner, and they'll show up here with the best time to go.")
                    }
                } else {
                    if !goodNow.isEmpty {
                        Section {
                            ForEach(goodNow) { row(for: $0) }
                        } header: {
                            Label("Good Time Now", systemImage: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    if !others.isEmpty {
                        Section("Your Picks") {
                            ForEach(others) { row(for: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Tip Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { rebuild() }
            .onChange(of: viewModel.lastRefreshed) { _, _ in rebuild() }
        }
    }

    @ViewBuilder
    private func row(for row: TipBoard.Row) -> some View {
        Button {
            dismiss()
            DeepLinkRouter.shared.open(.ride(id: row.id))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if row.isMustDo { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                        Text(row.name).font(.body.weight(.semibold)).lineLimit(2)
                    }
                    Text(caption(for: row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if row.isOperating, let wait = row.waitNow {
                    VStack(spacing: 0) {
                        Text("\(wait)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(row.isGoodNow ? Color.green : Color.primary)
                        Text("min").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Closed").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// "Usually ~70 now · Best today: 8pm (~20)"
    private func caption(for row: TipBoard.Row) -> String {
        var parts: [String] = []
        if let usual = row.usualNow { parts.append("Usually ~\(usual) now") }
        if let hour = row.bestHour, let wait = row.bestWait {
            parts.append("Best today: \(PlannerAI.hourLabel(hour)) (~\(wait))")
        }
        return parts.isEmpty ? "Not enough history yet — shows up after a few visits" : parts.joined(separator: " · ")
    }

    private func rebuild() {
        let resort = appState.selectedResort
        let planIds = Set(ItineraryService.shared.active(for: resort)?.rides.map(\.id) ?? [])
        let ids = appState.wishList.union(planIds)
        let rides = viewModel.allRides.filter { ids.contains($0.id) }
        guard !rides.isEmpty else { rows = []; return }

        let parks = viewModel.parksByGroup[resort] ?? []
        let planRides = PlanInputs.planRides(rides, parks: parks, fallbackParkName: parks.first?.name ?? "",
                                             context: context)
        let profiles = Dictionary(planRides.map { ($0.id, $0.waitByHour) }, uniquingKeysWith: { a, _ in a })
        let history = PlanInputs.history(for: Set(rides.map(\.id)), days: 14, context: context)
        let nowHour = Calendar.current.component(.hour, from: .now)
        let closeHour = parks.flatMap { viewModel.todaySchedule(for: $0) }
            .filter { !$0.isTicketedEvent }.compactMap(\.closingDate).max()
            .map { Calendar.current.component(.hour, from: $0) } ?? 22

        rows = rides.map { ride -> TipBoard.Row in
            let best = TipBoard.best(profile: profiles[ride.id] ?? [:], fromHour: nowHour, untilHour: closeHour)
            return TipBoard.Row(id: ride.id, name: ride.name, waitNow: ride.waitMinutes, isOperating: ride.isOperating,
                                usualNow: GoodTimeToRide.usual(samples: history[ride.id] ?? [])?.minutes,
                                bestHour: best?.hour, bestWait: best?.wait,
                                isMustDo: appState.wishList.contains(ride.id))
        }
        .sorted { a, b in
            if a.isMustDo != b.isMustDo { return a.isMustDo }
            return a.name < b.name
        }
    }
}
