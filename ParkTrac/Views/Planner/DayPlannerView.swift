import SwiftUI
import SwiftData

struct DayPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(WaitTimesViewModel.self) private var waitTimesVM

    @Query(sort: \PlanItem.sortOrder) private var allItems: [PlanItem]
    @Query(sort: \RideLog.riddenAt) private var rideLogs: [RideLog]
    @Query private var purchases: [PurchaseLog]
    @State private var showAddSheet = false
    @State private var showRecap = false
    @State private var showGuestPicker = false
    @State private var showSmartPlanner = false
    @State private var showAreaEntry = false
    @State private var showTipBoard = false
    @State private var showEndPlan = false
    /// Siri's "plan my day" request, passed to the Smart Planner once
    @State private var plannerRequest: String?

    /// True when pushed onto another NavigationStack (e.g. from Stats) — skips wrapping in our own.
    private let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var resort: String { appState.selectedResort.rawValue }

    private var todayItems: [PlanItem] {
        allItems.filter { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.resort == resort && !UndoDeleteCenter.shared.isHidden($0) }
    }
    private var llPasses: [PlanItem] {
        todayItems.filter { $0.kind == "ll" && !$0.isDone }
            .sorted { ($0.llReturnStart ?? .distantFuture) < ($1.llReturnStart ?? .distantFuture) }
    }
    private var planItems: [PlanItem] {
        todayItems.filter { $0.kind != "ll" }
    }

    private func liveWait(for item: PlanItem) -> Int? {
        guard let rideId = item.rideId, !rideId.isEmpty else { return nil }
        return waitTimesVM.allRides.first(where: { $0.id == rideId })?.waitMinutes
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        List {
            // Genie-style live plan (started from the Smart Planner)
            if let plan = ItineraryService.shared.active(for: appState.selectedResort) {
                Section {
                    NextUpCard(resort: appState.selectedResort)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    if let summary = plan.aiSummary {
                        Label(summary, systemImage: "apple.intelligence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array((ItineraryService.shared.live?.stops ?? []).enumerated()), id: \.offset) { _, stop in
                        HStack(spacing: 12) {
                            Text(stop.start, style: .time)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.title).font(.subheadline)
                                if stop.kind == "ride" {
                                    Text("~\(stop.waitMinutes) min wait" + (stop.walkMinutes > 0 ? " · \(stop.walkMinutes) min walk" : ""))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            if let rideId = stop.rideId {
                                Button("Done") { ItineraryService.shared.markDone(rideId) }.tint(.green)
                                Button("Skip") { ItineraryService.shared.skip(rideId) }.tint(.gray)
                            }
                        }
                    }
                    if let unscheduled = ItineraryService.shared.live?.unscheduled, !unscheduled.isEmpty {
                        Text("Won't fit before close: \(unscheduled.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button { showTipBoard = true } label: {
                        Label("Tip Board", systemImage: "list.star")
                    }
                    Button("End Today's Plan", role: .destructive) { showEndPlan = true }
                } header: {
                    Text("Today's Plan · Updates Live")
                } footer: {
                    Text("Re-plans from where you are with live waits. Rides you log with Rode It! drop off automatically. Shared with your other devices.")
                }
            }

            // Upcoming / current trip countdown (Trip Planner)
            if let countdown = TripService.shared.countdownText {
                NavigationLink {
                    TripPlannerView()
                } label: {
                    Label(countdown, systemImage: "airplane")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if !llPasses.isEmpty {
                Section {
                    ForEach(llPasses) { pass in
                        LLPassRow(pass: pass)
                            .swipeActions {
                                Button {
                                    pass.isDone = true
                                    LiveActivityManager.endReturnTime()
                                } label: {
                                    Label("Done", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                } header: {
                    Label(passSectionTitle, systemImage: "bolt.fill")
                        .foregroundStyle(.yellow)
                }
            }

            // USJ: Super Nintendo World needs an Area Timed Entry ticket from the USJ app
            if AreaEntry.isOffered(at: appState.selectedResort) {
                Section {
                    Button { showAreaEntry = true } label: {
                        Label("Log Area Timed Entry", systemImage: "ticket.fill")
                    }
                } footer: {
                    Text("Booked a Super Nintendo World entry time in the USJ app? Log it here for a reminder when it opens.")
                }
            }

            // Lightning Lane watches (notify-only; set from a ride's detail sheet)
            let watches = LightningLaneWatchService.shared.watches.filter(\.isToday)
            if !watches.isEmpty {
                Section {
                    ForEach(watches) { watch in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(watch.rideName).font(.subheadline.weight(.medium))
                                Text("Alert if a return opens \(watch.windowText)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let ll = waitTimesVM.allRides.first(where: { $0.id == watch.rideId })?.multiPass {
                                Text(ll.shortText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ll.isAvailable ? Color.orange : Color.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions {
                            Button("Stop", role: .destructive) {
                                LightningLaneWatchService.shared.remove(id: watch.id)
                            }
                        }
                    }
                } header: {
                    Label("Watching for Lightning Lane", systemImage: "bell.badge.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Book in the Disney app when an alert arrives. Swipe to stop watching.")
                }
            }

            // Reopen watches (set from a down/closed ride's detail sheet)
            let reopenWatches = ReopenWatchService.shared.watches.filter(\.isToday)
            if !reopenWatches.isEmpty {
                Section {
                    ForEach(reopenWatches) { watch in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(watch.rideName).font(.subheadline.weight(.medium))
                            Text("Alert when it's operating again")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions {
                            Button("Stop", role: .destructive) {
                                ReopenWatchService.shared.remove(rideId: watch.rideId)
                            }
                        }
                    }
                } header: {
                    Label("Watching for Reopen", systemImage: "bell.and.waves.left.and.right")
                        .foregroundStyle(.green)
                }
            }

            // Who's Coming section
            Section {
                if !appState.namedPartyMembers.isEmpty {
                    Label(NameList.format(appState.namedPartyMembers), systemImage: "person.2.fill")
                }
                if appState.todayGuestNames.isEmpty {
                    Button { showGuestPicker = true } label: {
                        Label("Add Guests", systemImage: "person.badge.plus")
                    }
                } else {
                    HStack {
                        Label("With \(NameList.format(appState.todayGuestNames))", systemImage: "person.badge.plus")
                        Spacer()
                        Button("Edit") { showGuestPicker = true }
                            .font(.caption)
                    }
                }
            } header: {
                Text("Who's Coming?")
            }

            // Car locator (sheet lives in ContentView)
            Section {
                if let spot = ParkingService.shared.spot(for: appState.selectedResort) {
                    Button { DeepLinkRouter.shared.open(.parking) } label: {
                        HStack {
                            Label(spot.summary.isEmpty ? spot.title : spot.summary, systemImage: "car.fill")
                                .lineLimit(2)
                            Spacer()
                            Text("Saved \(spot.savedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Shows your car on a map with walking directions")
                } else {
                    Button { DeepLinkRouter.shared.open(.parking) } label: {
                        Label("Save Parking Spot", systemImage: "car")
                    }
                }
            } header: {
                Text("Parking")
            }

            if planItems.isEmpty && llPasses.isEmpty {
                ContentUnavailableView {
                    Label("No Plans Yet", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Add rides, shows, or dining — or let Smart Planner build a day for you.")
                } actions: {
                    Button("Add to Plan") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Smart Planner") { showSmartPlanner = true }
                        .buttonStyle(.bordered)
                }
            } else if !planItems.isEmpty {
                Section("Today's Plan") {
                    ForEach(planItems) { item in
                        PlanItemRow(item: item, liveWait: liveWait(for: item))
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    UndoDeleteCenter.shared.delete([item], message: "Deleted \u{201C}\(item.title)\u{201D}", in: context)
                                }
                            }
                    }
                    .onMove { from, to in movePlanItems(planItems, from: from, to: to) }
                }
            }
        }
        // A pass leaves the list when marked Done (swipe or button)
        .sensoryFeedback(.success, trigger: llPasses.count) { old, new in new < old }
        .navigationTitle("My Day")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    Button { showSmartPlanner = true } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .accessibilityLabel("Smart Planner")
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add to plan")
                    Button { showRecap = true } label: {
                        Image(systemName: "sparkles.rectangle.stack")
                    }
                    .accessibilityLabel("Today's recap")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPlanItemView(resort: resort)
        }
        .sheet(isPresented: $showRecap) {
            NavigationStack {
                DayRecapView(date: .now, resort: appState.selectedResort)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showRecap = false } }
                    }
            }
        }
        .sheet(isPresented: $showGuestPicker) {
            GuestPickerSheet()
        }
        .sheet(isPresented: $showSmartPlanner, onDismiss: { plannerRequest = nil }) {
            SmartPlannerView(initialRequest: plannerRequest)
        }
        // Siri / thrilltrack://planner
        .onChange(of: DeepLinkRouter.shared.showSmartPlanner, initial: true) { _, show in
            guard show else { return }
            plannerRequest = DeepLinkRouter.shared.plannerRequest
            DeepLinkRouter.shared.plannerRequest = nil
            DeepLinkRouter.shared.showSmartPlanner = false
            showSmartPlanner = true
        }
        .sheet(isPresented: $showTipBoard) {
            TipBoardView()
        }
        .confirmationDialog("End today's plan?", isPresented: $showEndPlan, titleVisibility: .visible) {
            Button("End Plan", role: .destructive) { ItineraryService.shared.end() }
        }
        // Keep the live plan fresh when My Day opens (Wait Times re-plans on every refresh)
        .task {
            ItineraryService.shared.replan(viewModel: waitTimesVM, resort: appState.selectedResort,
                                           location: nil, context: context)
        }
        .sheet(isPresented: $showAreaEntry) {
            AreaEntrySheet(resort: appState.selectedResort)
        }
    }

    private var passSectionTitle: String {
        switch appState.selectedResort {
        case .disney, .universal: return "Lightning Lane / Express Pass"
        case .tokyoDisney:        return appState.selectedResort.returnPassNames.section
        case .universalJapan:     return "Express Pass & Timed Entry"
        }
    }

    /// Text recap of today at this resort (rides, plan progress, spending)
    private var todaySummary: String {
        let cal = Calendar.current
        let rides = rideLogs
            .filter { $0.resort == resort && cal.isDateInToday($0.riddenAt) }
            .map { DaySummary.Ride(name: $0.rideName, postedWait: $0.waitMinutes, actualWait: $0.actualWaitMinutes) }
        let spent = purchases
            .filter { $0.resort == resort && cal.isDateInToday($0.date) }
            .map(\.amount).reduce(0, +)
        return DaySummary.text(date: .now, resort: resort, rides: rides,
                               planDone: todayItems.filter(\.isDone).count,
                               planTotal: todayItems.count, spent: spent,
                               currencyCode: appState.selectedResort.currencyCode,
                               people: appState.namedPartyMembers + appState.todayGuestNames)
    }

    private func movePlanItems(_ items: [PlanItem], from: IndexSet, to: Int) {
        var reordered = items
        reordered.move(fromOffsets: from, toOffset: to)
        for (i, item) in reordered.enumerated() { item.sortOrder = i }
        try? context.save()
    }
}

// MARK: - Plan Item Row

private struct PlanItemRow: View {
    let item: PlanItem
    let liveWait: Int?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private var kindIcon: String {
        switch item.kind {
        case "ride":   return "figure.jumprope"
        case "show":   return "theatermasks.fill"
        case "dining": return "fork.knife"
        case "ll":     return "bolt.fill"
        default:       return "note.text"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { item.isDone.toggle() }
                if item.isDone && (item.kind == "ll" || item.kind == "aap") {
                    LiveActivityManager.endReturnTime()
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark \(item.title) not done" : "Mark \(item.title) done")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                HStack(spacing: 6) {
                    Image(systemName: kindIcon).font(.caption2).foregroundStyle(.secondary)
                    if let t = item.scheduledTime {
                        Text(Self.timeFmt.string(from: t)).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !item.parkName.isEmpty {
                        Text(item.parkName).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Live wait time badge
            if let wait = liveWait, !item.isDone {
                Text("\(wait)m")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(waitColor(wait), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.success, trigger: item.isDone) { _, done in done }
    }

    private func waitColor(_ minutes: Int) -> Color {
        if minutes < 30 { return .green }
        if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
    }
}

// MARK: - LL Pass Row

private struct LLPassRow: View {
    let pass: PlanItem

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private var windowText: String {
        guard let start = pass.llReturnStart else { return pass.title }
        if let end = pass.llReturnEnd, end != .distantFuture {
            return "\(Self.timeFmt.string(from: start)) – \(Self.timeFmt.string(from: end))"
        }
        return "After \(Self.timeFmt.string(from: start))"
    }

    private var urgencyColor: Color {
        guard let end = pass.llReturnEnd, end != .distantFuture else { return .blue }
        let mins = Int(end.timeIntervalSinceNow / 60)
        if mins < 0 { return Color.secondary }
        if mins < 15 { return .red }
        if mins < 30 { return .orange }
        return .green
    }

    private func timeUntilClose(_ now: Date) -> String? {
        guard let end = pass.llReturnEnd, end != .distantFuture else { return nil }
        let secs = end.timeIntervalSince(now)
        if secs < 0 { return "Expired" }
        let mins = Int(secs / 60)
        return mins < 60 ? "Closes in \(mins)m" : "Closes in \(mins/60)h \(mins%60)m"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Urgency stripe
            Rectangle()
                .fill(urgencyColor)
                .frame(width: 4)

            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pass.title).font(.subheadline.weight(.semibold))
                    Text(windowText).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    if let label = timeUntilClose(ctx.date) {
                        Text(label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(urgencyColor)
                    }
                }

                Button("Done") {
                    pass.isDone = true
                    LiveActivityManager.endReturnTime()
                }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}
