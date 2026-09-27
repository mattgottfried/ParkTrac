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
    /// Start on another day (My Day → "Plan a Future Day")
    var initialDay: Date? = nil

    /// The day being planned (today, or up to 60 days ahead)
    @State private var planDay: Date = Calendar.current.startOfDay(for: .now)
    private var isFuture: Bool { !Calendar.current.isDateInToday(planDay) }
    private var dayTitle: String { FutureDay.title(planDay) }
    private var planWeekday: Int { Calendar.current.component(.weekday, from: planDay) }

    /// Optional extras for Apple Intelligence ("dinner at 6:30, snack break at 3")
    @State private var notes = ""
    /// Apple Intelligence's explanation of the plan
    @State private var aiSummary: String?
    /// Shown when Apple Intelligence couldn't plan and ThrillTrack's planner did
    @State private var planNote: String?
    /// Genie-style interests (fill open time in the live plan)
    @State private var interests: Set<Interest> = []
    /// Apple Intelligence's ride order (ids) and the meals/breaks it read from the notes
    @State private var aiOrderIds: [String] = []
    @State private var aiExtras: [DayItinerary.Extra] = []
    private static let interestsKey = "plannerInterests"
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
        return viewModel.schedule(for: park, on: FutureDay.noon(planDay))
            .first { !$0.isExtraHours && !$0.isTicketedEvent }?
            .openingDate
    }

    private func effectiveStartTime() -> Date {
        let open = parkOpenTime ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: planDay) ?? planDay
        return isFuture ? open : max(open, .now)
    }

    /// Today: rides running now. Another day: every ride in the park (tonight they may all be closed).
    private var availableRides: [DisplayRide] {
        isFuture
            ? viewModel.filteredRides.filter { $0.status != "REFURBISHMENT" }
            : viewModel.filteredRides.filter { $0.isOperating && $0.waitMinutes != nil }
    }

    private var availableShows: [DisplayShow] {
        isFuture ? viewModel.currentShows.filter { !$0.showtimes.isEmpty } : viewModel.currentShows.filter { $0.nextShowtime != nil }
    }

    /// When a show plays on the planned day: today its next showing; another day, today's
    /// schedule moved onto that day (show schedules repeat day to day), first one after the start.
    private func showTime(_ show: DisplayShow) -> Date? {
        guard isFuture else { return show.nextShowtime }
        return show.showtimes.compactMap(\.startDate)
            .compactMap { FutureDay.moving($0, to: planDay) }
            .filter { $0 >= startTime }
            .min()
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
                        Button(isFuture ? "Save" : "Start Plan") { startPlan() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .task {
            viewModel.selectedGroup = appState.selectedResort
            await viewModel.loadAllParks()
            if let initialDay { planDay = Calendar.current.startOfDay(for: initialDay) }
            startTime = effectiveStartTime()
            let savedInterests = (UserDefaults.standard.stringArray(forKey: Self.interestsKey) ?? []).compactMap(Interest.init(rawValue:))
            interests = Set(ItineraryService.shared.active(for: appState.selectedResort)?.interests ?? savedInterests)
            for ride in availableRides where appState.wishList.contains(ride.id) {
                selectedRideIds.insert(ride.id)
            }
            // Siri: "Plan my day" — pick the rides/shows it names, then plan straight away
            if let initialRequest, !initialRequest.trimmingCharacters(in: .whitespaces).isEmpty {
                notes = initialRequest
                addNamedPicks(from: initialRequest)
                if !selectedRideIds.isEmpty || !selectedShowIds.isEmpty { await generate() }
            }
        }
        .onChange(of: viewModel.filterPark?.id) { _, _ in
            startTime = effectiveStartTime()
        }
        .onChange(of: planDay) { _, _ in
            startTime = effectiveStartTime()
            selectedShowIds = []
        }
    }

    // MARK: - Picking phase

    private var pickingView: some View {
        List {
            Section {
                DatePicker("Day", selection: $planDay,
                           in: Calendar.current.startOfDay(for: .now)...(Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now),
                           displayedComponents: .date)
                if isFuture {
                    DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                } else {
                    DatePicker("Start time", selection: $startTime, in: Date()..., displayedComponents: .hourAndMinute)
                }
            } footer: {
                if isFuture {
                    Text("Planning \(dayTitle): waits are estimated from typical \(planDay.formatted(.dateTime.weekday(.wide)))s — your visits and everyone's recorded waits. Show times are copied from today's schedule. On the day, Next Up takes over and re-plans live.")
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
                                if !isFuture, let m = ride.waitMinutes {
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
                                if let next = showTime(show) {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Interest.allCases) { interest in
                        let on = interests.contains(interest)
                        Button {
                            if on { interests.remove(interest) } else { interests.insert(interest) }
                        } label: {
                            Label(interest.label, systemImage: interest.systemImage)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(on ? appState.selectedResort.theme.primaryColor : Color(.systemFill),
                                            in: Capsule())
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Interests")
            } footer: {
                Text("Your plan suggests rides like these when they're short.")
            }

            if PlannerAI.isAvailable {
                Section {
                    TextField("e.g. Dinner at 6:30, Rise right before close, we love coasters", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Anything Else? (Optional)")
                } footer: {
                    Text("Apple Intelligence plans your picks around these, that day's dining reservations and the shows you chose — all on this iPhone.")
                }
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    Label(PlannerAI.isAvailable ? "Plan with Apple Intelligence" : "Build My Schedule",
                          systemImage: PlannerAI.isAvailable ? "apple.intelligence" : "wand.and.stars")
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
            Text(PlannerAI.isAvailable ? "Apple Intelligence is planning your day…" : "Building your schedule…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result phase

    private var resultView: some View {
        List {
            if isFuture {
                Section {
                    Label("Plan for \(planDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))", systemImage: "calendar")
                        .font(.headline)
                }
            }
            Section {
                if let aiSummary {
                    Label(aiSummary, systemImage: "apple.intelligence")
                        .font(.subheadline)
                } else {
                    Text("Rides are placed when they're usually shortest (from your past visits and live waits), with walking time between them. Shows, dining reservations and meals stay at their set times.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let planNote {
                    Text(planNote).font(.caption).foregroundStyle(.orange)
                }
                if !isFuture, let rain = RainForecastService.shared.headline(for: appState.selectedResort) {
                    RainHeadsUp(text: rain)
                }
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
                Button {
                    startPlan()
                } label: {
                    Label(isFuture ? "Save Plan for \(dayTitle)" : "Start Plan — Updates Live",
                          systemImage: isFuture ? "calendar.badge.checkmark" : "sparkles")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.selectedResort.theme.primaryColor)
                .listRowBackground(Color.clear)
            } footer: {
                Text(isFuture
                     ? "Saved in My Day → Coming Up. On \(dayTitle), Next Up starts it and re-plans from live waits."
                     : "Next Up re-plans all day from where you are and live waits; rides you log drop off.")
            }

            Section {
                Button("Add to My Day as a Fixed List") { saveToMyDay() }
                    .frame(maxWidth: .infinity)
                Button("Start Over") {
                    schedule = []
                    phase = .picking
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Names in Siri's request

    /// Tick any ride or show named in the text (Siri's "plan my day …")
    private func addNamedPicks(from text: String) {
        let c = PlanConstraints.fromPlainText(text, rideNames: availableRides.map(\.name),
                                              showNames: availableShows.map(\.name))
        for ride in availableRides where c.mustRide.contains(ride.name) { selectedRideIds.insert(ride.id) }
        for show in availableShows where c.includeShows.contains(show.name) { selectedShowIds.insert(show.id) }
    }

    // MARK: - Algorithm

    /// Latest regular closing time on the planned day for the park being planned
    private var parkCloseTime: Date? {
        let closings = (viewModel.filterPark ?? viewModel.currentParks.first).map { park in
            viewModel.schedule(for: park, on: FutureDay.noon(planDay))
                .filter { !$0.isTicketedEvent }
                .compactMap(\.closingDate)
        } ?? []
        return FutureDay.closeTime(closings: closings, day: planDay, start: startTime)
    }

    @MainActor
    private func generate() async {
        phase = .generating
        // Another day: everyone's typical waits for that weekday
        if isFuture {
            await CommunityHistoryService.shared.load(parkIds: viewModel.currentParks.map(\.id), weekday: planWeekday)
        }

        let rides = availableRides.filter { selectedRideIds.contains($0.id) }
        let shows = availableShows.filter { selectedShowIds.contains($0.id) }

        // Each ride's expected wait by hour: this phone's history, else live wait × park curve
        let since = Date.now.addingTimeInterval(-Double(RideProfile.historyDays) * 86_400)
        let ids = Set(rides.map(\.id))
        let records = ((try? modelContext.fetch(FetchDescriptor<WaitTimeRecord>(
            predicate: #Predicate { $0.recordedAt >= since }))) ?? []).filter { ids.contains($0.rideId) }
        var history: [String: [(date: Date, wait: Int)]] = [:]
        for r in records {
            if let w = r.waitMinutes { history[r.rideId, default: []].append((date: r.recordedAt, wait: w)) }
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
                                                                currentWait: ride.waitMinutes, parkCurve: curve,
                                                                community: isFuture
                                                                    ? CommunityHistoryService.shared.waitsByHour(
                                                                        rideId: ride.id, parkId: ride.parkId, weekday: planWeekday)
                                                                    : CommunityHistoryService.shared.waitsByHour(
                                                                        rideId: ride.id, parkId: ride.parkId),
                                                                pinCurrentHour: !isFuture),
                            isIndoor: RideMetadata.isIndoor(name: ride.name, resort: appState.selectedResort))
        }
        // Rain: outdoor rides move out of the wet hours
        let wetHours: Set<Int> = isFuture ? [] : RainForecastService.shared.wetHours(for: appState.selectedResort)

        // Fixed: chosen shows, today's dining reservations, meals/breaks from the request
        var fixed = shows.compactMap { show -> FixedEvent? in
            showTime(show).map { FixedEvent(title: show.name, kind: "show", start: $0, minutes: 25, parkName: parkName) }
        }
        let resortRaw = appState.selectedResort.rawValue
        let dining = (try? modelContext.fetch(FetchDescriptor<DiningReservation>())) ?? []
        fixed += dining
            .filter { $0.resort == resortRaw && !$0.isCompleted && Calendar.current.isDate($0.date, inSameDayAs: planDay)
                && $0.date > startTime }
            .map { FixedEvent(title: "Dining: \($0.restaurantName)", kind: "dining", start: $0.date, minutes: 75, parkName: parkName) }

        let end = parkCloseTime
        aiSummary = nil
        planNote = nil
        aiOrderIds = []
        aiExtras = []
        var plan = DayPlanBuilder.build(rides: planRides, fixed: fixed, start: startTime, end: end, wetHours: wetHours)

        // Apple Intelligence orders the picks; ThrillTrack times them
        if PlannerAI.isAvailable {
            let aiRides: [PlannerAI.PlanInput.Ride] = planRides.map {
                PlannerAI.PlanInput.Ride(name: $0.name, waitsByHour: $0.waitByHour,
                                         isMustDo: appState.wishList.contains($0.id), isIndoor: $0.isIndoor)
            }
            let aiShows: [PlannerAI.PlanInput.Fixed] = fixed.filter { $0.kind == "show" }.map {
                PlannerAI.PlanInput.Fixed(title: $0.title, time: $0.start)
            }
            let aiDining: [PlannerAI.PlanInput.Fixed] = fixed.filter { $0.kind == "dining" }.map {
                PlannerAI.PlanInput.Fixed(title: $0.title.replacingOccurrences(of: "Dining: ", with: ""), time: $0.start)
            }
            let input = PlannerAI.PlanInput(rides: aiRides, shows: aiShows, dining: aiDining,
                                            start: startTime, end: end, notes: notes,
                                            interests: Interest.allCases.filter { interests.contains($0) }.map(\.label),
                                            rainHours: Array(wetHours))
            do {
                let ai = try await PlannerAI.plan(input)
                let extras = PlannerAI.groundedExtras(ai.extraEvents, notes: notes).compactMap { e -> FixedEvent? in
                    guard let at = PlanConstraints.date(e.time, on: startTime) else { return nil }
                    return FixedEvent(title: e.title, kind: PlanConstraints.eventKind(for: e.title),
                                      start: at, minutes: e.minutes, parkName: parkName)
                }
                let ordered = PlannerAI.resolveOrder(ai.order, rides: planRides)
                plan = DayPlanBuilder.build(ordered: ordered, fixed: fixed + extras, start: startTime, end: end)
                aiSummary = ai.summary.isEmpty ? nil : ai.summary
                aiOrderIds = ordered.map(\.id)
                aiExtras = extras.map { DayItinerary.Extra(title: $0.title, kind: $0.kind, start: $0.start, minutes: $0.minutes) }
                interests.formUnion(Interest.from(ai.interests))
            } catch {
                planNote = "Apple Intelligence couldn't plan this one, so ThrillTrack's planner did."
            }
        }
        schedule = plan.stops.map { stop in
            ScheduledSlot(title: stop.title, kind: stop.kind, rideId: stop.rideId, parkName: stop.parkName,
                          startTime: stop.start, estimatedWaitMinutes: stop.waitMinutes,
                          totalDurationMinutes: stop.totalMinutes)
        }
        unscheduled = plan.unscheduled
        phase = .result
    }

    // MARK: - Start the live plan (Genie-style)

    private func startPlan() {
        let rides = availableRides.filter { selectedRideIds.contains($0.id) }
            .map { DayItinerary.Pick(id: $0.id, name: $0.name, parkId: $0.parkId) }
        let shows = availableShows.filter { selectedShowIds.contains($0.id) }
            .map { DayItinerary.Pick(id: $0.id, name: $0.name, parkId: $0.parkId) }
        let chosen = Interest.allCases.filter { interests.contains($0) }
        UserDefaults.standard.set(chosen.map(\.rawValue), forKey: Self.interestsKey)
        let plan = DayItinerary(
            day: Calendar.current.startOfDay(for: planDay), resortRaw: appState.selectedResort.rawValue,
            rides: rides, shows: shows, interests: chosen, notes: notes,
            aiOrder: aiOrderIds, aiSummary: aiSummary, extras: aiExtras)
        // Another day: keep it until then (My Day → Coming Up)
        if isFuture {
            ItineraryService.shared.saveUpcoming(plan)
            dismiss()
            return
        }
        ItineraryService.shared.start(plan)
        ItineraryService.shared.replan(viewModel: viewModel, resort: appState.selectedResort,
                                       location: nil, context: modelContext)
        dismiss()
    }

    // MARK: - Save to My Day

    private func saveToMyDay() {
        let maxOrder = (try? modelContext.fetch(FetchDescriptor<PlanItem>()))?.map(\.sortOrder).max() ?? 0
        for (i, slot) in schedule.enumerated() {
            let item = PlanItem(
                date: Calendar.current.startOfDay(for: planDay),
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
