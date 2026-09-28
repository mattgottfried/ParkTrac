import SwiftUI
import SwiftData

// MARK: - Defaults (pure, unit tested)

enum AddPlanDefaults {
    /// The next `step`-minute mark after `date`: 2:07 → 2:10 (step 5) / 2:30 (step 30).
    static func nextSlot(after date: Date, step: Int, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let next = (minutes / step + 1) * step
        return calendar.startOfDay(for: date).addingTimeInterval(Double(next) * 60)
    }

    /// Today's showtimes still ahead, soonest first.
    static func upcomingShowtimes(_ times: [Date], now: Date = .now, calendar: Calendar = .current) -> [Date] {
        times.filter { $0 > now && calendar.isDate($0, inSameDayAs: now) }.sorted()
    }
}

// MARK: - Add to My Day

/// One screen: pick the type, tap rides (several at once) or a show straight from the resort's
/// list, choose when (anytime, now, the ride's best time today, a showtime, or a set time), add.
/// Opened from a ride or show it starts compact with that item already chosen.
struct AddPlanItemView: View {
    let resort: String
    private let prefillRide: DisplayRide?
    private let prefillShow: DisplayShow?
    private let fallbackPark: String
    /// The day the items are for (start of day); a future day hides Now / Best and Lightning Lane
    private let planDate: Date
    private var isFutureDay: Bool { !Calendar.current.isDateInToday(planDate) }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(WaitTimesViewModel.self) private var waitTimesVM
    @Environment(AppState.self) private var appState
    @Query private var planItems: [PlanItem]

    enum Kind: String, CaseIterable, Identifiable {
        case ride, show, dining, ll, note
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ride: return "figure.jumprope"
            case .show: return "theatermasks.fill"
            case .dining: return "fork.knife"
            case .ll: return "bolt.fill"
            case .note: return "note.text"
            }
        }

        var color: Color {
            switch self {
            case .ride: return .blue
            case .show: return .purple
            case .dining: return .orange
            case .ll: return .yellow
            case .note: return .gray
            }
        }
    }

    enum When: Equatable { case anytime, now, best, custom, showtime }

    @State private var kind: Kind
    @State private var selectedRideIds: [String]
    @State private var selectedShowId: String?
    @State private var search = ""
    @State private var compact: Bool
    @State private var when: When
    @State private var customTime: Date
    @State private var showtime: Date?
    /// This ride's best hour left today (`WaitForecast.call`), when one ride is picked
    @State private var bestHour: Int?
    @State private var bestWait: Int?
    @State private var llStart: Date
    @State private var llEnd: Date
    @State private var diningTitle = ""
    @State private var diningPark = ""
    @State private var diningTime: Date
    @State private var noteText = ""
    @State private var notes = ""
    @State private var showLocationPicker = false

    init(resort: String, prefillRide: DisplayRide? = nil, prefillPark: String = "", prefillShow: DisplayShow? = nil,
         day: Date? = nil) {
        self.resort = resort
        self.prefillRide = prefillRide
        self.prefillShow = prefillShow
        self.fallbackPark = prefillPark
        let planDate = Calendar.current.startOfDay(for: day ?? .now)
        self.planDate = planDate
        _kind = State(initialValue: prefillShow != nil ? .show : .ride)
        _selectedRideIds = State(initialValue: prefillRide.map { [$0.id] } ?? [])
        _selectedShowId = State(initialValue: prefillShow?.id)
        _compact = State(initialValue: prefillRide != nil || prefillShow != nil)
        let nextShow = prefillShow?.nextShowtime
        _showtime = State(initialValue: nextShow)
        _when = State(initialValue: nextShow != nil ? .showtime : .anytime)
        let halfHour = Calendar.current.isDateInToday(planDate)
            ? AddPlanDefaults.nextSlot(after: .now, step: 30)
            : (Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: planDate) ?? planDate)
        _customTime = State(initialValue: halfHour)
        _diningTime = State(initialValue: halfHour)
        let fiveMinutes = AddPlanDefaults.nextSlot(after: .now, step: 5)
        _llStart = State(initialValue: fiveMinutes)
        _llEnd = State(initialValue: fiveMinutes.addingTimeInterval(3600))
    }

    // MARK: Data

    private var group: ParkGroup { ParkGroup(rawValue: resort) ?? .disney }

    /// The resort's parks, the one in focus on the map first
    private var parks: [ParkEntity] {
        let all = waitTimesVM.parksByGroup[group] ?? []
        guard let focus = waitTimesVM.filterPark, all.contains(where: { $0.id == focus.id }) else { return all }
        return [focus] + all.filter { $0.id != focus.id }
    }

    private func parkName(_ parkId: String) -> String {
        (waitTimesVM.parksByGroup[group] ?? []).first { $0.id == parkId }?.name ?? fallbackPark
    }

    private func rides(in park: ParkEntity) -> [DisplayRide] {
        waitTimesVM.allRides
            .filter { $0.parkId == park.id }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { a, b in
                if a.isOperating != b.isOperating { return a.isOperating }
                return a.name < b.name
            }
    }

    private func shows(in park: ParkEntity) -> [DisplayShow] {
        waitTimesVM.allShowsForPlanning
            .filter { $0.parkId == park.id }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.nextShowtime ?? .distantFuture) < ($1.nextShowtime ?? .distantFuture) }
    }

    private func ride(_ id: String) -> DisplayRide? {
        waitTimesVM.allRides.first { $0.id == id } ?? (prefillRide?.id == id ? prefillRide : nil)
    }

    private var selectedRides: [DisplayRide] { selectedRideIds.compactMap { ride($0) } }

    private var selectedShow: DisplayShow? {
        guard let selectedShowId else { return nil }
        return waitTimesVM.allShowsForPlanning.first { $0.id == selectedShowId }
            ?? (prefillShow?.id == selectedShowId ? prefillShow : nil)
    }

    /// Rides already in today's My Day at this resort
    private var plannedIds: Set<String> {
        Set(planItems.filter { $0.resort == resort && Calendar.current.isDateInToday($0.date) }.compactMap(\.rideId))
    }

    private var passName: String { group.isOrlando ? "Lightning Lane" : group.returnPassNames.free }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !compact { kindPicker }
                    switch kind {
                    case .ride: rideSection
                    case .show: showSection
                    case .ll: lightningLaneSection
                    case .dining: diningSection
                    case .note: noteSection
                    }
                    if kind != .note { notesField }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { addButton }
            .navigationTitle(kind == .ll ? "Log \(passName)" : (isFutureDay ? "Add to \(FutureDay.title(planDate))" : "Add to My Day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: selectedRideIds) { computeBest() }
            .sheet(isPresented: $showLocationPicker) {
                let alwaysTrue = Binding<Bool>(get: { true }, set: { _ in })
                LocationPickerView(resort: resort, category: "Food", selectedPark: $diningPark,
                                   selectedLocation: $diningTitle, isAPEligible: alwaysTrue)
                    .presentationDetents([.large])
            }
        }
        .presentationDetents(compact ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selectedRideIds)
    }

    // MARK: Type

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(Kind.allCases.filter { !(isFutureDay && $0 == .ll) }) { k in
                Button {
                    withAnimation(.spring(response: 0.25)) { switchKind(to: k) }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: k.icon).font(.title3.weight(.semibold))
                        Text(label(for: k)).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(kind == k ? Color.white : k.color)
                    .background(kind == k ? k.color : k.color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == k ? .isSelected : [])
            }
        }
    }

    private func label(for k: Kind) -> String {
        switch k {
        case .ride: return "Ride"
        case .show: return "Show"
        case .dining: return "Dining"
        case .ll: return group.returnPassNames.short
        case .note: return "Note"
        }
    }

    private func switchKind(to k: Kind) {
        if k == .ll { selectedRideIds = Array(selectedRideIds.prefix(1)) }
        if k != .ride && k != .ll { selectedRideIds = [] }
        if k != .show { selectedShowId = nil }
        if k == .ride && (when == .showtime) { when = .anytime }
        kind = k
    }

    // MARK: Rides

    @ViewBuilder
    private var rideSection: some View {
        if compact, let first = selectedRides.first {
            rideHeader(first)
        } else {
            ridePicker(multiple: true)
        }
        if !selectedRideIds.isEmpty { whenCard }
    }

    private func rideHeader(_ ride: DisplayRide) -> some View {
        card {
            HStack(spacing: 12) {
                WaitTile(ride: ride, size: 52, numberSize: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(parkName(ride.parkId)).font(.caption).foregroundStyle(.secondary)
                    if plannedIds.contains(ride.id) {
                        Text("Already in today's plan").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                Button("Change") { withAnimation { compact = false } }
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func ridePicker(multiple: Bool) -> some View {
        searchField(prompt: "Search rides")
        ForEach(parks, id: \.id) { park in
            let list = rides(in: park)
            if !list.isEmpty {
                card(park.name) {
                    ForEach(list) { ride in
                        rideRow(ride, multiple: multiple)
                    }
                }
            }
        }
    }

    private func rideRow(_ ride: DisplayRide, multiple: Bool) -> some View {
        let selected = selectedRideIds.contains(ride.id)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { toggle(ride.id, multiple: multiple) }
        } label: {
            HStack(spacing: 12) {
                WaitTile(ride: ride, size: 40, numberSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(ride.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if appState.wishList.contains(ride.id) {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        }
                        if ride.isOperating, let group = ParkGroup(rawValue: resort), RideMetadata.hasSingleRider(name: ride.name, resort: group) {
                            Image(systemName: "person.fill").font(.caption2).foregroundStyle(.blue)
                        }
                    }
                    if plannedIds.contains(ride.id) {
                        Text("Already in today's plan").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.6))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(ride.isOperating || ride.status == "DOWN" ? 1 : 0.55)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ id: String, multiple: Bool) {
        if !multiple {
            selectedRideIds = [id]
        } else if let i = selectedRideIds.firstIndex(of: id) {
            selectedRideIds.remove(at: i)
        } else {
            selectedRideIds.append(id)
        }
    }

    /// When: Anytime · Now · Best ~8 PM · Pick a time
    private var whenCard: some View {
        card("When") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Anytime", selected: when == .anytime) { when = .anytime }
                    if !isFutureDay {
                        chip("Now", selected: when == .now) { when = .now }
                    }
                    if !isFutureDay, let bestHour, let bestWait, selectedRideIds.count == 1 {
                        chip("Best ~\(RainForecast.hourText(bestHour)) · ~\(bestWait)m", icon: "star.fill",
                             selected: when == .best) { when = .best }
                    }
                    chip("Pick a time", icon: "clock", selected: when == .custom) { when = .custom }
                }
            }
            if when == .custom {
                DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
            }
        }
    }

    private func computeBest() {
        bestHour = nil
        bestWait = nil
        defer { if bestHour == nil && when == .best { when = .anytime } }
        guard selectedRideIds.count == 1, let ride = selectedRides.first, ride.isOperating else { return }
        let parkList = waitTimesVM.parksByGroup[group] ?? []
        let profile = PlanInputs.planRides([ride], parks: parkList, fallbackParkName: fallbackPark,
                                           resort: group, context: context).first?.waitByHour ?? [:]
        let closing = parkList.first { $0.id == ride.parkId }
            .map { waitTimesVM.todaySchedule(for: $0) }?
            .filter { !$0.isTicketedEvent }
            .compactMap(\.closingDate)
            .max()
        let nowHour = Calendar.current.component(.hour, from: .now)
        let call = WaitForecast.call(profile: profile, nowHour: nowHour, currentWait: ride.waitMinutes,
                                     lastHour: WaitForecast.lastHour(closing: closing) ?? 21)
        if case .waitUntil(let hour, let wait, _) = call {
            bestHour = hour
            bestWait = wait
        }
    }

    // MARK: Shows

    @ViewBuilder
    private var showSection: some View {
        if compact, let show = selectedShow {
            card {
                HStack(spacing: 12) {
                    Image(systemName: "theatermasks.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 52, height: 52)
                        .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.name).font(.headline)
                        Text(parkName(show.parkId)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Change") { withAnimation { compact = false } }
                        .font(.subheadline.weight(.medium))
                }
            }
        } else {
            searchField(prompt: "Search shows")
            ForEach(parks, id: \.id) { park in
                let list = shows(in: park)
                if !list.isEmpty {
                    card(park.name) {
                        ForEach(list) { show in showRow(show) }
                    }
                }
            }
        }
        if let show = selectedShow { showtimeCard(show) }
    }

    private func showRow(_ show: DisplayShow) -> some View {
        let selected = selectedShowId == show.id
        return Button {
            selectedShowId = show.id
            showtime = showtimes(for: show).first
            when = showtime != nil ? .showtime : .custom
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(showtimes(for: show).first.map { "\(isFutureDay ? "First" : "Next"): \(timeText($0))" }
                         ?? (isFutureDay ? "No showtimes listed" : "No more showtimes today"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.6))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func showtimeCard(_ show: DisplayShow) -> some View {
        let upcoming = showtimes(for: show)
        return card("Showtime") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(upcoming, id: \.self) { time in
                        chip(timeText(time), selected: when == .showtime && showtime == time) {
                            showtime = time
                            when = .showtime
                        }
                    }
                    chip("Pick a time", icon: "clock", selected: when == .custom) { when = .custom }
                }
            }
            if when == .custom {
                DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
            }
        }
    }

    // MARK: Lightning Lane

    @ViewBuilder
    private var lightningLaneSection: some View {
        if compact, let first = selectedRides.first {
            rideHeader(first)
        } else {
            ridePicker(multiple: false)
        }
        card("Return window") {
            DatePicker("From", selection: $llStart, displayedComponents: .hourAndMinute)
            DatePicker("To", selection: $llEnd, displayedComponents: .hourAndMinute)
            Text("ThrillTrack adds it to My Day, starts a Live Activity and reminds you before it closes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Dining / Note

    @ViewBuilder
    private var diningSection: some View {
        Button {
            showLocationPicker = true
        } label: {
            card("Restaurant") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diningTitle.isEmpty ? "Choose restaurant…" : diningTitle)
                            .font(.subheadline)
                            .foregroundStyle(diningTitle.isEmpty ? Color.secondary : Color.primary)
                        if !diningPark.isEmpty {
                            Text(diningPark).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        card("Time") {
            DatePicker("Reservation", selection: $diningTime, displayedComponents: .hourAndMinute)
        }
    }

    private var noteSection: some View {
        card {
            TextField("Write a note…", text: $noteText, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var notesField: some View {
        card("Notes") {
            TextField("Optional…", text: $notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    // MARK: Add

    private var addTitle: String {
        switch kind {
        case .ride:
            let n = selectedRideIds.count
            return n > 1 ? "Add \(n) Rides to My Day" : "Add to My Day"
        case .ll:
            return "Log \(passName) Return"
        default:
            return "Add to My Day"
        }
    }

    private var canAdd: Bool {
        switch kind {
        case .ride: return !selectedRideIds.isEmpty
        case .show: return selectedShow != nil
        case .ll: return selectedRides.count == 1 && llEnd > llStart
        case .dining: return !diningTitle.trimmingCharacters(in: .whitespaces).isEmpty
        case .note: return !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var addButton: some View {
        Button(action: save) {
            Label(addTitle, systemImage: kind == .ll ? "bolt.fill" : "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(kind == .ll ? Color.black : Color.white)
                .background(canAdd ? kind.color : Color.gray.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// The time a ride or show is planned for (nil = anytime)
    private var plannedTime: Date? {
        switch when {
        case .anytime: return nil
        case .now: return .now
        case .best:
            return bestHour.flatMap { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: .now) }
        case .custom: return customTime
        case .showtime: return showtime
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var order = (planItems.map(\.sortOrder).max() ?? 0) + 1
        func insert(title: String, kind: String, rideId: String?, park: String, time: Date?) {
            context.insert(PlanItem(date: planDate, scheduledTime: time, title: title, kind: kind, rideId: rideId,
                                    parkName: park, resort: resort, notes: trimmedNotes, sortOrder: order))
            order += 1
        }

        switch kind {
        case .ride:
            for ride in selectedRides {
                insert(title: ride.name, kind: "ride", rideId: ride.id, park: parkName(ride.parkId), time: plannedTime)
            }
        case .show:
            if let show = selectedShow {
                insert(title: show.name, kind: "show", rideId: nil, park: parkName(show.parkId), time: plannedTime)
            }
        case .ll:
            if let ride = selectedRides.first {
                // PlanItem + Live Activity + closing-soon reminder, like every other return
                ReturnTimeLogger.log(passLabel: passName, isOpenEnded: false, rideId: ride.id, rideName: ride.name,
                                     parkName: parkName(ride.parkId), resort: resort,
                                     returnStart: llStart, returnEnd: llEnd, context: context)
            }
        case .dining:
            insert(title: diningTitle.trimmingCharacters(in: .whitespaces), kind: "dining", rideId: nil,
                   park: diningPark, time: diningTime)
        case .note:
            insert(title: noteText.trimmingCharacters(in: .whitespacesAndNewlines), kind: "note", rideId: nil,
                   park: "", time: nil)
        }
        try? context.save()
        dismiss()
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func searchField(prompt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $search).autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chip(_ title: String, icon: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The show's times on the day being planned: today's upcoming ones, or on a future day
    /// today's schedule moved onto that day
    private func showtimes(for show: DisplayShow) -> [Date] {
        let times = show.showtimes.compactMap(\.startDate)
        guard isFutureDay else { return AddPlanDefaults.upcomingShowtimes(times) }
        return times.compactMap { FutureDay.moving($0, to: planDate) }.sorted()
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
