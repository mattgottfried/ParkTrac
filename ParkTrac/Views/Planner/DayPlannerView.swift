import SwiftUI
import SwiftData

struct DayPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(WaitTimesViewModel.self) private var waitTimesVM

    @Query(sort: \PlanItem.sortOrder) private var allItems: [PlanItem]
    @State private var showAddSheet = false
    @State private var showGuestPicker = false
    @State private var showSmartPlanner = false

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var resort: String { appState.selectedResort.rawValue }

    private var todayItems: [PlanItem] {
        allItems.filter { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.resort == resort }
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
        NavigationStack {
            List {
                if !llPasses.isEmpty {
                    Section {
                        ForEach(llPasses) { pass in
                            LLPassRow(pass: pass)
                                .swipeActions {
                                    Button("Done", role: .destructive) {
                                        pass.isDone = true
                                        LiveActivityManager.endReturnTime()
                                        NotificationService.shared.cancelLLReminder(passId: pass.id.uuidString)
                                    }
                                }
                        }
                    } header: {
                        Label("Lightning Lane / Express Pass", systemImage: "bolt.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                // Who's Coming section
                Section {
                    if appState.todayGuestIds.isEmpty {
                        Button { showGuestPicker = true } label: {
                            Label("Add Guests", systemImage: "person.badge.plus")
                        }
                    } else {
                        HStack {
                            Label("\(appState.todayGuestIds.count) guest\(appState.todayGuestIds.count == 1 ? "" : "s") coming", systemImage: "person.2.fill")
                            Spacer()
                            Button("Edit") { showGuestPicker = true }
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Who's Coming?")
                }

                if planItems.isEmpty && llPasses.isEmpty {
                    ContentUnavailableView("No Plans Yet", systemImage: "calendar.badge.plus",
                        description: Text("Tap + to add rides, shows, or dining to today's plan."))
                } else if !planItems.isEmpty {
                    Section("Today's Plan") {
                        ForEach(planItems) { item in
                            PlanItemRow(item: item, liveWait: liveWait(for: item))
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) { context.delete(item) }
                                }
                        }
                        .onMove { from, to in movePlanItems(planItems, from: from, to: to) }
                    }
                }
            }
            .navigationTitle("My Day")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button { showSmartPlanner = true } label: {
                            Image(systemName: "wand.and.stars")
                        }
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPlanItemView(resort: resort)
            }
            .sheet(isPresented: $showGuestPicker) {
                GuestPickerSheet()
            }
            .sheet(isPresented: $showSmartPlanner) {
                SmartPlannerView()
            }
        }
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
                    .font(.system(size: 22))
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

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
                    NotificationService.shared.cancelLLReminder(passId: pass.id.uuidString)
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
