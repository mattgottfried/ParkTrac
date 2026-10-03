import SwiftUI
import SwiftData

struct SpendingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \PurchaseLog.date, order: .reverse) private var allPurchases: [PurchaseLog]

    @State private var showAddSheet = false
    @State private var addPurchasePrefill: String? = nil
    @State private var showBudgetSheet = false
    @State private var tripService = TripService.shared

    private var resort: String { appState.selectedResort.rawValue }
    private var resortPurchases: [PurchaseLog] { allPurchases.filter { $0.resort == resort && !UndoDeleteCenter.shared.isHidden($0) } }
    private var budget: Double { appState.tripBudget(for: appState.selectedResort) }

    private var todayTotal: Double {
        resortPurchases.filter { Calendar.current.isDateInToday($0.date) }.map(\.amount).reduce(0, +)
    }
    private var tripTotal: Double { resortPurchases.map(\.amount).reduce(0, +) }
    /// Same currency as `resortPurchases`, so no cross-currency summing — a separate year-over-year
    /// view for an annual pass holder who's logged more than one year at this resort.
    private var yearTotal: Double {
        YearToDateSpend.total(purchases: resortPurchases.map { (amount: $0.amount, date: $0.date) },
                              year: Calendar.current.component(.year, from: .now))
    }

    /// The return-pass category name follows the resort — "Lightning Lane" at Disney, "Express
    /// Pass" at Universal Orlando, etc. — rather than Disney's name everywhere.
    private var returnPassCategory: String { appState.selectedResort.returnPassNames.section }
    private var categories: [String] { ["Food", "Merchandise", "Tickets", returnPassCategory, "Other"] }
    /// Japan resorts log yen; show ≈ dollars beside it
    private var showsDollars: Bool { appState.selectedResort.currencyCode == "JPY" }
    private let currency = CurrencyConverter.shared
    private var categoryColors: [String: Color] {
        ["Food": .orange, "Merchandise": .blue, "Tickets": .purple,
         returnPassCategory: .yellow, "Other": .gray]
    }
    static let snackPresets = ["Popcorn", "Churro", "Soda", "Ice Cream", "Pretzel", "Turkey Leg"]

    var body: some View {
        // Pushed from the Stats tab's NavigationStack — don't nest another.
        Group {
            List {
                Section {
                    HStack(spacing: 0) {
                        spendStat(label: "Today", value: todayTotal, color: .blue)
                        Divider()
                        spendStat(label: "This Trip", value: tripTotal, color: .green)
                        Divider()
                        spendStat(label: "This Year", value: yearTotal, color: .purple)
                    }
                    .frame(height: 70)
                }

                Section {
                    if budget > 0 {
                        budgetProgress
                    } else {
                        Button {
                            showBudgetSheet = true
                        } label: {
                            Label("Set a Trip Budget", systemImage: "target")
                        }
                    }
                }

                if !resortPurchases.isEmpty {
                    Section("By Category") {
                        ForEach(categories, id: \.self) { cat in
                            let total = resortPurchases.filter { $0.category == cat }.map(\.amount).reduce(0, +)
                            if total > 0 {
                                HStack {
                                    Circle().fill(categoryColors[cat] ?? .gray).frame(width: 10, height: 10)
                                    Text(cat)
                                    Spacer()
                                    Text(total, format: .currency(code: appState.selectedResort.currencyCode)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.snackPresets, id: \.self) { snack in
                                Button {
                                    addPurchasePrefill = snack
                                    showAddSheet = true
                                } label: {
                                    Text(snack)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: {
                    Text("Quick Snack")
                } footer: {
                    Text("Fills in the item — you still type the price.")
                }

                Section("All Purchases") {
                    if resortPurchases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No purchases logged yet.").foregroundStyle(.secondary).font(.subheadline)
                            Button {
                                addPurchasePrefill = nil
                                showAddSheet = true
                            } label: {
                                Label("Add Purchase", systemImage: "plus.circle.fill")
                            }
                        }
                    } else {
                        ForEach(resortPurchases) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.note.isEmpty ? p.category : p.note)
                                        .font(.subheadline)
                                    Text("\(p.category) · \(p.date, style: .date)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(p.amount, format: .currency(code: appState.selectedResort.currencyCode))
                                        .font(.subheadline.weight(.semibold))
                                    if showsDollars {
                                        Text(currency.dollarsText(yen: p.amount))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let doomed = indexSet.map { resortPurchases[$0] }
                            UndoDeleteCenter.shared.delete(doomed, message: doomed.count == 1 ? "Purchase deleted" : "\(doomed.count) purchases deleted", in: context)
                        }
                    }
                }
            }
            .navigationTitle("Spending")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: PassSavingsView()) {
                        Label("Pass Savings", systemImage: "dollarsign.arrow.circlepath")
                            .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addPurchasePrefill = nil
                        showAddSheet = true
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add purchase")
                }
            }
            .sheet(isPresented: $showAddSheet) { AddPurchaseView(resort: resort, prefillNote: addPurchasePrefill) }
            .sheet(isPresented: $showBudgetSheet) { TripBudgetSheet(resort: appState.selectedResort) }
            .task { if showsDollars { await currency.refresh() } }
        }
    }

    private func spendStat(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .currency(code: appState.selectedResort.currencyCode))
                .font(.title3.weight(.bold)).foregroundStyle(color)
            if showsDollars {
                Text(currency.dollarsText(yen: value)).font(.caption2).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Budget

    private var budgetFraction: Double { budget > 0 ? min(tripTotal / budget, 1.5) : 0 }
    private var budgetColor: Color {
        let f = tripTotal / max(budget, 0.01)
        return f >= 1 ? .red : f >= 0.8 ? .orange : .green
    }

    /// Only when the Trip Planner has dates that cover the selected resort and haven't ended.
    private var pacing: BudgetPacing? {
        guard let trip = tripService.trip, trip.resorts.contains(appState.selectedResort) else { return nil }
        return BudgetPacer.pace(budget: budget, spent: tripTotal, today: .now, tripEnd: trip.endDate)
    }

    private var budgetProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trip Budget")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Edit") { showBudgetSheet = true }
                    .font(.caption)
            }
            ProgressView(value: min(budgetFraction, 1))
                .tint(budgetColor)
            HStack {
                Text(tripTotal, format: .currency(code: appState.selectedResort.currencyCode))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(budgetColor)
                Text("of")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(budget, format: .currency(code: appState.selectedResort.currencyCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if tripTotal > budget {
                    Text("\(tripTotal - budget, format: .currency(code: appState.selectedResort.currencyCode)) over")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                } else {
                    Text("\(budget - tripTotal, format: .currency(code: appState.selectedResort.currencyCode)) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let pacing {
                Text("\(pacing.perDay, format: .currency(code: appState.selectedResort.currencyCode))/day for \(pacing.remainingDays) more day\(pacing.remainingDays == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(pacing.perDay < 0 ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TripBudgetSheet: View {
    let resort: ParkGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(resort.currencyCode)
                            .foregroundStyle(.secondary)
                        TextField("e.g. 500", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("A rough target for this trip's spending. Set it to 0 to hide the tracker.")
                }
            }
            .navigationTitle("Trip Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.setTripBudget(Double(amount) ?? 0, for: resort)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let existing = appState.tripBudget(for: resort)
                amount = existing > 0 ? String(format: "%.0f", existing) : ""
            }
        }
    }
}

struct AddPurchaseView: View {
    let resort: String
    /// Prefills category + note (e.g. a snack quick-add) — the amount is always left blank
    /// so the real price is typed in, never guessed.
    var prefillNote: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amount = ""
    @State private var category = "Food"
    @State private var note = ""
    @State private var isAPEligible = false
    @State private var selectedPark = ""
    @State private var showLocationPicker = false
    private var categories: [String] {
        let returnPass = ParkGroup(rawValue: resort)?.returnPassNames.section ?? "Lightning Lane"
        return ["Food", "Merchandise", "Tickets", returnPass, "Other"]
    }
    /// Japan resorts are logged in yen
    private var isYen: Bool { ParkGroup(rawValue: resort)?.currencyCode == "JPY" }

    init(resort: String, prefillNote: String? = nil) {
        self.resort = resort
        self.prefillNote = prefillNote
        _note = State(initialValue: prefillNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(isYen ? "¥" : "$")
                        TextField(isYen ? "0" : "0.00", text: $amount).keyboardType(isYen ? .numberPad : .decimalPad)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if isYen, let yen = Double(amount), yen > 0 {
                        Text(CurrencyConverter.shared.dollarsText(yen: yen))
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }
                if category == "Food" || category == "Merchandise" {
                    Section {
                        Button {
                            showLocationPicker = true
                        } label: {
                            HStack {
                                Text(note.isEmpty ? "Choose location…" : note)
                                    .foregroundStyle(note.isEmpty ? Color.secondary : Color.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Toggle("AP Discount Eligible", isOn: $isAPEligible)
                    } header: {
                        Text("Location")
                    } footer: {
                        Text("AP discount only applies at select locations.")
                            .font(.caption)
                    }
                } else {
                    Section("Note (optional)") {
                        TextField("e.g. Mickey pretzel", text: $note)
                    }
                }
            }
            .navigationTitle("Add Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(amount), value > 0 {
                            context.insert(PurchaseLog(amount: value, category: category, resort: resort, note: note, isAPEligible: isAPEligible))
                            try? context.save()
                            dismiss()
                        }
                    }
                    .disabled(Double(amount) == nil || (Double(amount) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                resort: resort,
                category: category,
                selectedPark: $selectedPark,
                selectedLocation: $note,
                isAPEligible: $isAPEligible
            )
            .presentationDetents([.large])
        }
    }
}
