import SwiftUI
import SwiftData

/// Genie-style "Next Up": the next stop of today's live plan, with Done / Skip, what comes
/// after, and rides that fit the party's interests. Shown on Wait Times and in My Day.
struct NextUpCard: View {
    let resort: ParkGroup

    @Environment(\.modelContext) private var context
    @Environment(WaitTimesViewModel.self) private var viewModel
    @State private var itineraries = ItineraryService.shared

    var body: some View {
        if let plan = itineraries.active(for: resort) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Next Up", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text("\(plan.doneIds.count) of \(plan.rides.count) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let rain = RainForecastService.shared.headline(for: resort) {
                    RainHeadsUp(text: rain)
                }

                if let stop = itineraries.nextStop {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stop.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        Text(detail(for: stop))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    if let rideId = stop.rideId {
                        HStack(spacing: 10) {
                            Button {
                                itineraries.markDone(rideId)
                                replan()
                            } label: {
                                Label("Done", systemImage: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Button {
                                itineraries.skip(rideId)
                                replan()
                            } label: {
                                Label("Skip", systemImage: "forward.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button {
                                DeepLinkRouter.shared.open(.ride(id: rideId))
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                            }
                            .accessibilityLabel("Ride details")
                        }
                    }

                    let after = Array((itineraries.live?.stops ?? []).dropFirst().prefix(2))
                    if !after.isEmpty {
                        Text("Then: " + after.map { "\($0.title) (\(timeText($0.start)))" }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text(plan.remainingRides.isEmpty
                         ? "All your picks are done 🎉"
                         : "Planning from live waits…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !itineraries.suggestions.isEmpty {
                    Divider()
                    Text("Fits your interests — short waits now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(itineraries.suggestions, id: \.id) { s in
                        HStack {
                            Text(s.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(s.wait) min")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Button {
                                let parkId = viewModel.allRides.first { $0.id == s.id }?.parkId ?? ""
                                itineraries.add(.init(id: s.id, name: s.name, parkId: parkId))
                                replan()
                            } label: {
                                Image(systemName: "plus.circle.fill").font(.title3)
                            }
                            .accessibilityLabel("Add \(s.name) to the plan")
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Get in line ~2:16 PM · ~35 min wait · 6 min walk" / "6:30 PM"
    private func detail(for stop: PlannedStop) -> String {
        let base = ParkDayActivity.detail(for: stop)
        guard stop.kind == "ride" else { return base }
        // "Get in line ~2:16 PM · ~35 min wait · 6 min walk"
        var parts = base.components(separatedBy: " · ")
        parts.insert("~\(stop.waitMinutes) min wait", at: 1)
        return parts.joined(separator: " · ")
    }

    private func replan() {
        itineraries.replan(viewModel: viewModel, resort: resort, location: nil, context: context)
    }
}

/// "🌧 Rain likely 3–5 PM · indoor rides planned then" (Next Up, Smart Planner)
struct RainHeadsUp: View {
    let text: String

    var body: some View {
        Label("\(text) · indoor rides planned then", systemImage: "cloud.rain.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.blue.opacity(0.12), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
