import SwiftUI
import SwiftData

struct DayPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @Query(sort: \PlanItem.sortOrder) private var allItems: [PlanItem]
    @State private var showAddSheet = false

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

    var body: some View {
        NavigationStack {
            List {
                if !llPasses.isEmpty {
                    Section {
                        ForEach(llPasses) { pass in
                            LLPassRow(pass: pass)
                                .swipeActions {
                                    Button("Done", role: .destructive) { pass.isDone = true }
                                }
                        }
                    } header: {
                        Label("Lightning Lane / Express Pass", systemImage: "bolt.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                if planItems.isEmpty && llPasses.isEmpty {
                    ContentUnavailableView("No Plans Yet", systemImage: "calendar.badge.plus",
                        description: Text("Tap + to add rides, shows, or dining to today's plan."))
                } else if !planItems.isEmpty {
                    Section("Today's Plan") {
                        ForEach(planItems) { item in
                            PlanItemRow(item: item)
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
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPlanItemView(resort: resort)
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
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
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
        }
        .padding(.vertical, 2)
    }
}

// MARK: - LL Pass Row

private struct LLPassRow: View {
    let pass: PlanItem

    private var windowText: String {
        guard let start = pass.llReturnStart, let end = pass.llReturnEnd else { return pass.title }
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm"
        return "\(fmt.string(from: start))–\(fmt.string(from: end))"
    }

    private var timeUntilClose: String? {
        guard let end = pass.llReturnEnd else { return nil }
        let secs = end.timeIntervalSinceNow
        if secs < 0 { return "Expired" }
        let mins = Int(secs / 60)
        return mins < 60 ? "Closes in \(mins)m" : "Closes in \(mins/60)h \(mins%60)m"
    }

    private var urgencyColor: Color {
        guard let end = pass.llReturnEnd else { return .secondary }
        let mins = Int(end.timeIntervalSinceNow / 60)
        if mins < 0 { return .secondary }
        if mins < 15 { return .red }
        if mins < 30 { return .orange }
        return .green
    }

    var body: some View {
        HStack {
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(pass.title).font(.subheadline.weight(.semibold))
                Text(windowText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let label = timeUntilClose {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(urgencyColor)
            }
        }
    }
}
