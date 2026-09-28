import SwiftUI
import SwiftData

/// Waits are lowest right at rope drop — for a guest without a return-time pass, being first
/// at the gate for the day's Must-Dos is the single best lever left. This times your starred
/// Must-Dos from the park's opening (nearest-neighbour ordered, since at rope drop everyone's
/// wait is near zero and walking distance is what actually costs you time), reusing the same
/// scheduler the Smart Planner uses for the actual timing.
enum RopeDropPlan {
    /// Nearest-neighbour route through the Must-Dos — nothing about wait time matters yet at
    /// park open, only how far apart they are.
    static func order(_ rides: [PlanRide]) -> [PlanRide] {
        PlanOrdering.lessWalking(rides)
    }
}

struct RopeDropPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(WaitTimesViewModel.self) private var viewModel

    @State private var stops: [PlannedStop] = []
    @State private var openTime: Date?
    @State private var parkName = ""

    private var resort: ParkGroup { appState.selectedResort }

    var body: some View {
        NavigationStack {
            List {
                if appState.wishList.isEmpty {
                    ContentUnavailableView {
                        Label("No Must-Dos Yet", systemImage: "star")
                    } description: {
                        Text("Star a few rides as Must-Do and they'll show up here, timed from park open.")
                    }
                } else if let openTime {
                    Section {
                        Label("\(parkName) opens at \(openTime.formatted(date: .omitted, time: .shortened))",
                              systemImage: "sunrise.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Waits are lowest right at open — the earlier you're through the gate, the more of this holds. This route is by walking distance, not predicted wait, since everything's short this early.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if stops.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing to Plan", systemImage: "questionmark.circle")
                        } description: {
                            Text("Your Must-Dos may be at a different park, or already sold out for today.")
                        }
                    } else {
                        Section("Rope Drop Order") {
                            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                                stopRow(index: index, stop: stop)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Hours Yet", systemImage: "clock")
                    } description: {
                        Text("Today's opening time for \(parkName.isEmpty ? "this park" : parkName) isn't published yet.")
                    }
                }
            }
            .navigationTitle("Rope Drop Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { build() }
        }
    }

    private func stopRow(index: Int, stop: PlannedStop) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.orange, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.title).font(.subheadline.weight(.semibold))
                Text("\(stop.start.formatted(date: .omitted, time: .shortened)) · ~\(stop.waitMinutes) min wait"
                    + (index > 0 ? " · \(stop.walkMinutes) min walk" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func build() {
        guard let park = viewModel.filterPark ?? viewModel.currentParks.first else { return }
        parkName = park.name
        let today = viewModel.schedule(for: park, on: .now)
            .first { !$0.isExtraHours && !$0.isTicketedEvent }
        guard let open = today?.openingDate else { openTime = nil; return }
        openTime = open
        let close = today?.closingDate

        let mustDoRides = viewModel.allRides.filter { appState.wishList.contains($0.id) && $0.parkId == park.id }
        guard !mustDoRides.isEmpty else { stops = []; return }

        let planRides = PlanInputs.planRides(mustDoRides, parks: viewModel.currentParks,
                                             fallbackParkName: park.name, resort: resort, context: context)
        let ordered = RopeDropPlan.order(planRides)
        let plan = DayPlanBuilder.build(ordered: ordered, fixed: [], start: open, end: close)
        stops = plan.stops
    }
}
