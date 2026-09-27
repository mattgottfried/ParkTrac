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

    @Environment(WaitTimesViewModel.self) private var viewModel
    /// From Siri ("Plan my day in ThrillTrack") or a deep link — run once the rides load
    var initialRequest: String? = nil

    @State private var request = ""
    @State private var isInterpreting = false
    @State private var requestNote: String?
    /// Meals / breaks at a set time from the request
    @State private var requestedEvents: [FixedEvent] = []
    @State private var endTime: Date?
    @State private var unscheduled: [String] = []
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
            if let initialRequest, !initialRequest.trimmingCharacters(in: .whitespaces).isEmpty {
                request = initialRequest
                await planFromRequest(autoBuild: true)
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
                TextField(PlannerAI.isAvailable
                          ? "e.g. Dinner at 6:30, want Seven Dwarfs and Space Mountain, no water rides"
                          : "Type the rides you want, e.g. Seven Dwarfs, Space Mountain",
                          text: $request, axis: .vertical)
                    .lineLimit(1...4)
                Button {
                    Task { await planFromRequest(autoBuild: true) }
                } label: {
                    HStack {
                        Label(isInterpreting ? "Thinking…" : "Plan It", systemImage: PlannerAI.isAvailable ? "apple.intelligence" : "wand.and.stars")
                        Spacer()
                        if isInterpreting { ProgressView() }
                    }
                }
                .disabled(isInterpreting || request.trimmingCharacters(in: .whitespaces).isEmpty)
                if let requestNote {
                    Text(requestNote).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Tell Me Your Plan")
            } footer: {
                Text(PlannerAI.isAvailable
                     ? "Apple Intelligence reads your request on this iPhone; ThrillTrack then builds the schedule from live and past waits."
                     : "Or pick rides and shows below.")
            }

            Section {
                DatePicker("Start time", selection: $startTime, in: Date()..., displayedComponents: .hourAndMinute)
                if let endTime {
                    HStack {
                        Text("Finish by")
                        Spacer()
                        Text(endTime, style: .time).foregroundStyle(.secondary)
                        Button { self.endTime = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Remove finish time")
                    }
                }
                ForEach(Array(requestedEvents.enumerated()), id: \.offset) { index, event in
                    HStack {
                        Label(event.title, systemImage: event.kind == "dining" ? "fork.knife" : "cup.and.saucer")
                        Spacer()
                        Text(event.start, style: .time).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button("Remove", role: .destructive) { requestedEvents.remove(at: index) } }
                }
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
                Text("Rides are placed when they're usually shortest (from your past visits and live waits), with walking time between them. Shows, dining reservations and meals stay at their set times.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !unscheduled.isEmpty {
                Section {
                    Text("Didn't fit before the park closes: \(unscheduled.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.orange)
                }
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

    // MARK: - Request (Apple Intelligence or plain text)

    @MainActor
    private func planFromRequest(autoBuild: Bool) async {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let rideNames = availableRides.map(\.name)
        let showNames = availableShows.map(\.name)
        var constraints: PlanConstraints
        if PlannerAI.isAvailable {
            isInterpreting = true
            defer { isInterpreting = false }
            do {
                constraints = try await PlannerAI.interpret(text, rideNames: rideNames, showNames: showNames)
            } catch {
                constraints = PlanConstraints.fromPlainText(text, rideNames: rideNames, showNames: showNames)
                requestNote = "Apple Intelligence couldn't read that, so I matched ride names instead."
            }
        } else {
            constraints = PlanConstraints.fromPlainText(text, rideNames: rideNames, showNames: showNames)
        }
        apply(constraints)
        if autoBuild, !selectedRideIds.isEmpty || !selectedShowIds.isEmpty {
            await generate()
        }
    }

    @MainActor
    private func apply(_ c: PlanConstraints) {
        let rides = availableRides.map { (id: $0.id, name: $0.name,
                                          info: RideMetadata.info(for: $0.name, resort: appState.selectedResort)) }
        selectedRideIds = c.selectRides(from: rides, fallback: selectedRideIds)
        for show in availableShows where c.includeShows.contains(where: { PlanConstraints.matches($0, show.name) }) {
            selectedShowIds.insert(show.id)
        }
        if let start = PlanConstraints.date(c.startTime, on: .now), start > .now { startTime = start }
        endTime = PlanConstraints.date(c.endTime, on: .now)
        requestedEvents = c.fixedEvents.compactMap { e in
            guard let at = PlanConstraints.date(e.time, on: .now) else { return nil }
            let isMeal = ["dinner", "lunch", "breakfast", "dining", "meal", "eat"].contains { e.title.lowercased().contains($0) }
            return FixedEvent(title: e.title, kind: isMeal ? "dining" : "break", start: at, minutes: e.minutes, parkName: parkName)
        }
        let picked = selectedRideIds.count
        if requestNote == nil || !PlannerAI.isAvailable {
            requestNote = picked == 0
                ? "I didn't recognize any ride names — pick rides below."
                : "Planning \(picked) ride\(picked == 1 ? "" : "s")" + (requestedEvents.isEmpty ? "." : " around \(requestedEvents.count) set time\(requestedEvents.count == 1 ? "" : "s").")
        }
    }

    // MARK: - Algorithm

    /// Latest regular closing time today for the park being planned
    private var parkCloseTime: Date? {
        guard let park = viewModel.filterPark ?? viewModel.currentParks.first else { return nil }
        return viewModel.todaySchedule(for: park)
            .filter { !$0.isTicketedEvent }
            .compactMap(\.closingDate).max()
    }

    @MainActor
    private func generate() async {
        phase = .generating

        let rides = availableRides.filter { selectedRideIds.contains($0.id) }
        let shows = availableShows.filter { selectedShowIds.contains($0.id) }

        // Each ride's expected wait by hour: this phone's history, else live wait × park curve
        let since = Date.now.addingTimeInterval(-Double(RideProfile.historyDays) * 86_400)
        let ids = Set(rides.map(\.id))
        let records = ((try? modelContext.fetch(FetchDescriptor<WaitTimeRecord>(
            predicate: #Predicate { $0.recordedAt >= since }))) ?? []).filter { ids.contains($0.rideId) }
        var history: [String: [(date: Date, wait: Int)]] = [:]
        for r in records {
            if let w = r.waitMinutes { history[r.rideId, default: []].append((r.recordedAt, w)) }
        }

        let planRides = rides.map { ride -> PlanRide in
            let park = viewModel.currentParks.first { $0.id == ride.parkId }?.name ?? parkName
            var curve: [Int: Double] = [:]
            for hour in RideProfile.dayHours {
                curve[hour] = CommunityBaselineService.shared.adjustedHourlyAvg(for: park, hour: hour)
            }
            return PlanRide(id: ride.id, name: ride.name, parkName: park,
                            latitude: ride.coordinate?.latitude, longitude: ride.coordinate?.longitude,
                            waitByHour: RideProfile.waitsByHour(samples: history[ride.id] ?? [],
                                                                currentWait: ride.waitMinutes, parkCurve: curve))
        }

        // Fixed: chosen shows, today's dining reservations, meals/breaks from the request
        var fixed = shows.compactMap { show -> FixedEvent? in
            show.nextShowtime.map { FixedEvent(title: show.name, kind: "show", start: $0, minutes: 25, parkName: parkName) }
        }
        let resortRaw = appState.selectedResort.rawValue
        let dining = (try? modelContext.fetch(FetchDescriptor<DiningReservation>())) ?? []
        fixed += dining
            .filter { $0.resort == resortRaw && !$0.isCompleted && Calendar.current.isDateInToday($0.date) && $0.date > startTime }
            .map { FixedEvent(title: "Dining: \($0.restaurantName)", kind: "dining", start: $0.date, minutes: 75, parkName: parkName) }
        fixed += requestedEvents

        let plan = DayPlanBuilder.build(rides: planRides, fixed: fixed, start: startTime,
                                        end: endTime ?? parkCloseTime)
        schedule = plan.stops.map { stop in
            ScheduledSlot(title: stop.title, kind: stop.kind, rideId: stop.rideId, parkName: stop.parkName,
                          startTime: stop.start, estimatedWaitMinutes: stop.waitMinutes,
                          totalDurationMinutes: stop.totalMinutes)
        }
        unscheduled = plan.unscheduled
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
