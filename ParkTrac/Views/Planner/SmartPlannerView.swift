import SwiftUI
import SwiftData

// MARK: - Scheduled slot (output of the algorithm)

struct ScheduledSlot: Identifiable {
    let id = UUID()
    let title: String
    let kind: String          // "ride" | "show" | "dining"
    let rideId: String?
    let parkName: String
    let startTime: Date
    let estimatedWaitMinutes: Int
    let totalDurationMinutes: Int  // wait + ride + walk
}

// MARK: - Smart Planner View

struct SmartPlannerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = WaitTimesViewModel()
    @State private var selectedRideIds: Set<String> = []
    @State private var selectedShowIds: Set<String> = []
    @State private var startTime: Date = .now
    @State private var schedule: [ScheduledSlot] = []
    @State private var phase: Phase = .picking

    private enum Phase { case picking, generating, result }

    private var parkName: String {
        viewModel.filterPark?.name ?? viewModel.currentParks.first?.name ?? ""
    }

    private var parkOpenTime: Date? {
        guard let park = viewModel.filterPark ?? viewModel.currentParks.first else { return nil }
        return viewModel.todaySchedule(for: park)
            .first { !$0.isExtraHours && !$0.isTicketedEvent }?
            .openingDate
    }

    private func effectiveStartTime() -> Date {
        let open = parkOpenTime ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        return max(open, .now)
    }

    private var availableRides: [DisplayRide] {
        viewModel.filteredRides.filter { $0.isOperating && $0.waitMinutes != nil }
    }

    private var availableShows: [DisplayShow] {
        viewModel.currentShows.filter { $0.nextShowtime != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .picking:    pickingView
                case .generating: generatingView
                case .result:     resultView
                }
            }
            .navigationTitle("Smart Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if phase == .result {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save to My Day") { saveToMyDay() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .task {
            viewModel.selectedGroup = appState.selectedResort
            await viewModel.loadAllParks()
            startTime = effectiveStartTime()
            for ride in availableRides where appState.wishList.contains(ride.id) {
                selectedRideIds.insert(ride.id)
            }
        }
        .onChange(of: viewModel.filterPark?.id) { _, _ in
            startTime = effectiveStartTime()
        }
    }

    // MARK: - Picking phase

    private var pickingView: some View {
        List {
            Section {
                DatePicker("Start time", selection: $startTime, in: Date()..., displayedComponents: .hourAndMinute)
            }

            // Park chip picker
            if !viewModel.currentParks.isEmpty {
                Section("Park") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.currentParks) { park in
                                Button(park.name) {
                                    viewModel.filterPark = park
                                    selectedRideIds = []
                                    selectedShowIds = []
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(viewModel.filterPark?.id == park.id
                                    ? appState.selectedResort.theme.primaryColor
                                    : Color(.systemFill))
                                .foregroundStyle(viewModel.filterPark?.id == park.id ? .white : .primary)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }

            // Rides
            if viewModel.isLoading {
                Section("Rides") {
                    ProgressView("Loading wait times…")
                }
            } else if !availableRides.isEmpty {
                Section {
                    ForEach(availableRides) { ride in
                        HStack {
                            Image(systemName: selectedRideIds.contains(ride.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedRideIds.contains(ride.id) ? .green : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.name).font(.subheadline)
                                if let m = ride.waitMinutes {
                                    Text("\(m) min wait now").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if appState.wishList.contains(ride.id) {
                                Image(systemName: "star.fill")
                                    .font(.caption).foregroundStyle(.yellow)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedRideIds.contains(ride.id) { selectedRideIds.remove(ride.id) }
                            else { selectedRideIds.insert(ride.id) }
                        }
                    }
                } header: {
                    Text("Rides (\(selectedRideIds.count) selected)")
                }
            }

            // Shows
            if !availableShows.isEmpty {
                Section {
                    ForEach(availableShows) { show in
                        HStack {
                            Image(systemName: selectedShowIds.contains(show.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedShowIds.contains(show.id) ? .blue : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(show.name).font(.subheadline)
                                if let next = show.nextShowtime {
                                    Text(next, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedShowIds.contains(show.id) { selectedShowIds.remove(show.id) }
                            else { selectedShowIds.insert(show.id) }
                        }
                    }
                } header: {
                    Text("Shows (\(selectedShowIds.count) selected)")
                }
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    Label("Build My Schedule", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.selectedResort.theme.primaryColor)
                .disabled(selectedRideIds.isEmpty && selectedShowIds.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Generating phase

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Building your schedule…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result phase

    private var resultView: some View {
        List {
            Section {
                Text("Rides are ordered to minimize predicted wait time. Shows are locked at their scheduled time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(schedule) { slot in
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(slot.startTime, style: .time)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        Text(slotEndTime(slot), style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(width: 52, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Image(systemName: kindIcon(slot.kind))
                                .font(.caption2).foregroundStyle(.secondary)
                            if slot.estimatedWaitMinutes > 0 {
                                Text("~\(slot.estimatedWaitMinutes)m predicted wait")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    waitBadge(slot)
                }
                .padding(.vertical, 2)
            }

            Section {
                Button("Start Over") {
                    schedule = []
                    phase = .picking
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Algorithm

    @MainActor
    private func generate() async {
        phase = .generating

        let rides = availableRides.filter { selectedRideIds.contains($0.id) }
        let shows = availableShows.filter { selectedShowIds.contains($0.id) }

        // Predict best hour for each ride
        struct RideCandidate {
            let ride: DisplayRide
            let bestHour: Int
            let estWait: Int
        }

        var candidates: [RideCandidate] = []
        for ride in rides {
            let result = WaitTimePredictionService.predict(
                rideId: ride.id,
                parkGroup: appState.selectedResort,
                parkName: parkName,
                currentStatus: ride.status,
                context: modelContext
            )
            let startHour = Calendar.current.component(.hour, from: startTime)
            let relevant = result.hourlyAverages.filter { $0.hour >= startHour }
            let best = relevant.min { $0.averageWait < $1.averageWait }
            let bestHour = best?.hour ?? startHour
            let estWait = Int((best?.averageWait ?? Double(ride.waitMinutes ?? 30)).rounded())
            candidates.append(RideCandidate(ride: ride, bestHour: bestHour, estWait: estWait))
        }

        // Sort candidates by their best hour
        candidates.sort { $0.bestHour < $1.bestHour }

        // Build fixed show slots
        struct ShowSlot {
            let show: DisplayShow
            let time: Date
        }
        let showSlots = shows
            .compactMap { show -> ShowSlot? in
                guard let t = show.nextShowtime else { return nil }
                return ShowSlot(show: show, time: t)
            }
            .sorted { $0.time < $1.time }

        // Greedy scheduling
        var result: [ScheduledSlot] = []
        var currentTime = startTime
        var remaining = candidates
        var showQueue = showSlots

        while !remaining.isEmpty || !showQueue.isEmpty {
            // Check if next show is coming up within 60 min
            if let nextShow = showQueue.first {
                let minsUntilShow = nextShow.time.timeIntervalSince(currentTime) / 60
                if minsUntilShow <= 5 {
                    // Lock in the show
                    result.append(ScheduledSlot(
                        title: nextShow.show.name,
                        kind: "show",
                        rideId: nil,
                        parkName: parkName,
                        startTime: nextShow.time,
                        estimatedWaitMinutes: 0,
                        totalDurationMinutes: 25
                    ))
                    let showDur = 25.0
                    currentTime = nextShow.time.addingTimeInterval(showDur * 60)
                    showQueue.removeFirst()
                    continue
                }
            }

            guard !remaining.isEmpty else {
                // Only shows left — fast-forward to next show
                if let nextShow = showQueue.first {
                    currentTime = nextShow.time
                }
                break
            }

            // Pick the best ride for the current hour
            let currentHour = Calendar.current.component(.hour, from: currentTime)
            let idx = remaining.indices.min { a, b in
                let waitA = remaining[a].estWait + abs(remaining[a].bestHour - currentHour)
                let waitB = remaining[b].estWait + abs(remaining[b].bestHour - currentHour)
                return waitA < waitB
            } ?? 0

            let candidate = remaining[idx]
            remaining.remove(at: idx)

            let wait = candidate.estWait
            let rideDuration = 15   // typical ride duration + walk
            let total = wait + rideDuration

            // Check if show will conflict
            if let nextShow = showQueue.first {
                let minsUntilShow = nextShow.time.timeIntervalSince(currentTime) / 60
                if minsUntilShow < Double(total) && minsUntilShow > 5 {
                    // Skip this ride for now and wait for show
                    remaining.insert(candidate, at: 0)
                    currentTime = nextShow.time
                    continue
                }
            }

            result.append(ScheduledSlot(
                title: candidate.ride.name,
                kind: "ride",
                rideId: candidate.ride.id,
                parkName: viewModel.currentParks.first { $0.id == candidate.ride.parkId }?.name ?? parkName,
                startTime: currentTime,
                estimatedWaitMinutes: wait,
                totalDurationMinutes: total
            ))
            currentTime = currentTime.addingTimeInterval(Double(total) * 60)
        }

        // Append any remaining shows that didn't get placed
        for show in showQueue {
            result.append(ScheduledSlot(
                title: show.show.name,
                kind: "show",
                rideId: nil,
                parkName: parkName,
                startTime: show.time,
                estimatedWaitMinutes: 0,
                totalDurationMinutes: 25
            ))
        }

        schedule = result.sorted { $0.startTime < $1.startTime }
        phase = .result
    }

    // MARK: - Save to My Day

    private func saveToMyDay() {
        let maxOrder = (try? modelContext.fetch(FetchDescriptor<PlanItem>()))?.map(\.sortOrder).max() ?? 0
        for (i, slot) in schedule.enumerated() {
            let item = PlanItem(
                scheduledTime: slot.startTime,
                title: slot.title,
                kind: slot.kind,
                rideId: slot.rideId,
                parkName: slot.parkName,
                resort: appState.selectedResort.rawValue,
                sortOrder: maxOrder + i + 1
            )
            modelContext.insert(item)
        }
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Helpers

    private func slotEndTime(_ slot: ScheduledSlot) -> Date {
        slot.startTime.addingTimeInterval(Double(slot.totalDurationMinutes) * 60)
    }

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "ride":   return "figure.jumprope"
        case "show":   return "theatermasks.fill"
        case "dining": return "fork.knife"
        default:       return "note.text"
        }
    }

    @ViewBuilder
    private func waitBadge(_ slot: ScheduledSlot) -> some View {
        if slot.kind == "show" {
            Image(systemName: "theatermasks.fill")
                .font(.caption).foregroundStyle(.blue)
        } else if slot.estimatedWaitMinutes > 0 {
            Text("\(slot.estimatedWaitMinutes)m")
                .font(.caption.weight(.bold))
                .foregroundStyle(slot.estimatedWaitMinutes < 30 ? .green
                                 : slot.estimatedWaitMinutes < 60 ? .orange : .red)
        }
    }

}
