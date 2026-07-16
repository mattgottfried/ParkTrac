import SwiftUI
import SwiftData

struct PassSavingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VisitSaving.date, order: .reverse) private var allSavings: [VisitSaving]
    @Query(sort: \PurchaseLog.date, order: .reverse) private var allPurchases: [PurchaseLog]

    @State private var showAddVisit = false
    @State private var editingDisneyCost = false
    @State private var editingUniversalCost = false

    // MARK: - Discount rates per pass tier
    // Source: Official Disney/Universal passholder discount pages (verified May 2026)

    // All Disney AP tiers receive the same discount rates
    private var disneyMerchRate: Double { appState.disneyPassTier != .none ? 0.20 : 0 }
    private var disneyFoodRate:  Double { appState.disneyPassTier != .none ? 0.10 : 0 }

    // Universal rates vary by tier
    private var universalMerchRate: Double {
        switch appState.universalPassTier {
        case .premier:              return 0.15
        case .preferred:            return 0.10
        case .power, .select, .seasonal, .none: return 0
        }
    }

    private var universalFoodRate: Double {
        switch appState.universalPassTier {
        case .premier:              return 0.15
        case .preferred:            return 0.10
        case .power, .select, .seasonal, .none: return 0
        }
    }

    // MARK: - Savings calculations

    private var disneyVisitSavings: Double {
        allSavings.filter { $0.resort == ParkGroup.disney.rawValue }.map(\.gateValue).reduce(0, +)
    }

    private var universalVisitSavings: Double {
        allSavings.filter { $0.resort == ParkGroup.universal.rawValue }.map(\.gateValue).reduce(0, +)
    }

    private var disneyParkingSavings: Double {
        allSavings.filter { $0.resort == ParkGroup.disney.rawValue }.map(\.parkingValue).reduce(0, +)
    }

    private var universalParkingSavings: Double {
        allSavings.filter { $0.resort == ParkGroup.universal.rawValue }.map(\.parkingValue).reduce(0, +)
    }

    private func parkingVisitCount(_ resort: String) -> Int {
        allSavings.filter { $0.resort == resort && $0.parkingValue > 0 }.count
    }

    private var disneyPurchases: [PurchaseLog] {
        allPurchases.filter { $0.resort == ParkGroup.disney.rawValue }
    }

    private var universalPurchases: [PurchaseLog] {
        allPurchases.filter { $0.resort == ParkGroup.universal.rawValue }
    }

    // Only purchases marked AP eligible count toward discount savings
    private var disneyMerchSpend: Double {
        disneyPurchases.filter { $0.category == "Merchandise" && $0.isAPEligible }.map(\.amount).reduce(0, +)
    }
    private var disneyFoodSpend: Double {
        disneyPurchases.filter { $0.category == "Food" && $0.isAPEligible }.map(\.amount).reduce(0, +)
    }
    private var universalMerchSpend: Double {
        universalPurchases.filter { $0.category == "Merchandise" && $0.isAPEligible }.map(\.amount).reduce(0, +)
    }
    private var universalFoodSpend: Double {
        universalPurchases.filter { $0.category == "Food" && $0.isAPEligible }.map(\.amount).reduce(0, +)
    }

    // Amounts entered are post-discount (what the user actually paid).
    // To recover the original discount amount: savings = paid × rate / (1 − rate)
    private var disneyDiscountSavings: Double {
        let merch = disneyMerchRate > 0 ? disneyMerchSpend * disneyMerchRate / (1 - disneyMerchRate) : 0
        let food  = disneyFoodRate  > 0 ? disneyFoodSpend  * disneyFoodRate  / (1 - disneyFoodRate)  : 0
        return merch + food
    }
    private var universalDiscountSavings: Double {
        let mRate = universalMerchRate
        let fRate = universalFoodRate
        let merch = mRate > 0 ? universalMerchSpend * mRate / (1 - mRate) : 0
        let food  = fRate > 0 ? universalFoodSpend  * fRate / (1 - fRate) : 0
        return merch + food
    }

    private var disneyTotalSavings: Double { disneyVisitSavings + disneyParkingSavings + disneyDiscountSavings }
    private var universalTotalSavings: Double { universalVisitSavings + universalParkingSavings + universalDiscountSavings }

    private var disneyNet: Double { disneyTotalSavings - appState.disneyPassCost }
    private var universalNet: Double { universalTotalSavings - appState.universalPassCost }

    // MARK: - Body

    var body: some View {
        Form {
            // Pass cost entry
            if appState.disneyPassTier != .none {
                Section("Disney Pass Cost") {
                    passCostRow(
                        label: appState.disneyPassTier.rawValue,
                        cost: appState.disneyPassCost,
                        placeholder: disneyPassPricePlaceholder,
                        onChange: { appState.disneyPassCost = $0 }
                    )
                }
            }

            if appState.universalPassTier != .none {
                Section("Universal Pass Cost") {
                    passCostRow(
                        label: appState.universalPassTier.rawValue,
                        cost: appState.universalPassCost,
                        placeholder: universalPassPricePlaceholder,
                        onChange: { appState.universalPassCost = $0 }
                    )
                }
            }

            // Disney summary
            if appState.disneyPassTier != .none {
                Section {
                    savingsSummaryCard(
                        resort: ParkGroup.disney.rawValue,
                        visitSavings: disneyVisitSavings,
                        parkingSavings: disneyParkingSavings,
                        parkingCount: parkingVisitCount(ParkGroup.disney.rawValue),
                        discountSavings: disneyDiscountSavings,
                        totalSavings: disneyTotalSavings,
                        passCost: appState.disneyPassCost,
                        net: disneyNet,
                        visitCount: allSavings.filter { $0.resort == ParkGroup.disney.rawValue }.count,
                        merchRate: disneyMerchRate,
                        foodRate: disneyFoodRate,
                        merchSpend: disneyMerchSpend,
                        foodSpend: disneyFoodSpend
                    )
                } header: {
                    Text("Disney Savings")
                }
            }

            // Universal summary
            if appState.universalPassTier != .none {
                Section {
                    savingsSummaryCard(
                        resort: ParkGroup.universal.rawValue,
                        visitSavings: universalVisitSavings,
                        parkingSavings: universalParkingSavings,
                        parkingCount: parkingVisitCount(ParkGroup.universal.rawValue),
                        discountSavings: universalDiscountSavings,
                        totalSavings: universalTotalSavings,
                        passCost: appState.universalPassCost,
                        net: universalNet,
                        visitCount: allSavings.filter { $0.resort == ParkGroup.universal.rawValue }.count,
                        merchRate: universalMerchRate,
                        foodRate: universalFoodRate,
                        merchSpend: universalMerchSpend,
                        foodSpend: universalFoodSpend
                    )
                } header: {
                    Text("Universal Savings")
                }
            }

            // Visit log
            Section {
                if allSavings.isEmpty {
                    Text("Tap + to log your first visit and how much you saved on gate tickets.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(allSavings) { saving in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saving.note.isEmpty ? saving.resort : saving.note)
                                    .font(.subheadline)
                                Text(saving.date, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                                if saving.parkingValue > 0 {
                                    Text("Ticket \(saving.gateValue, format: .currency(code: "USD")) + \(saving.parkingType.lowercased()) parking \(saving.parkingValue, format: .currency(code: "USD"))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(saving.totalValue, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(allSavings[i]) }
                        try? modelContext.save()
                    }
                }
            } header: {
                HStack {
                    Text("Visit Savings")
                    Spacer()
                    Button { showAddVisit = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Log the gate ticket price and parking you would have paid for each visit. Discounts on food and merchandise are calculated automatically from your Spending log.")
                    .font(.caption)
            }

            if appState.disneyPassTier == .none && appState.universalPassTier == .none {
                Section {
                    Text("Set up your annual passes in Annual Passes to start tracking savings.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Pass Savings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddVisit) {
            AddVisitSavingSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Subviews

    private func passCostRow(label: String, cost: Double, placeholder: String, onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer()
            CurrencyField(value: cost, placeholder: placeholder, onChange: onChange)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(cost > 0 ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func savingsSummaryCard(
        resort: String,
        visitSavings: Double,
        parkingSavings: Double,
        parkingCount: Int,
        discountSavings: Double,
        totalSavings: Double,
        passCost: Double,
        net: Double,
        visitCount: Int,
        merchRate: Double,
        foodRate: Double,
        merchSpend: Double,
        foodSpend: Double
    ) -> some View {
        // Big net number
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(net >= 0 ? "+" : "")
                .font(.title2.weight(.bold))
                .foregroundStyle(net >= 0 ? .green : .red)
            Text(abs(net), format: .currency(code: "USD"))
                .font(.title2.weight(.bold))
                .foregroundStyle(net >= 0 ? .green : .red)
            Spacer()
            Text(net >= 0 ? "pass paid off" : "not yet paid off")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Progress bar if cost is set
        if passCost > 0 {
            let progress = min(totalSavings / passCost, 1.0)
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(net >= 0 ? Color.green : Color.orange)
                            .frame(width: geo.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)
                Text("\(Int(progress * 100))% of \(passCost, format: .currency(code: "USD")) pass cost recovered")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        Divider()

        // Ticket savings row
        HStack {
            Label("Gate tickets (\(visitCount) visit\(visitCount == 1 ? "" : "s"))", systemImage: "ticket.fill")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(visitSavings, format: .currency(code: "USD"))
                .font(.subheadline.weight(.medium)).foregroundStyle(.green)
        }

        // Parking savings row
        if parkingSavings > 0 {
            HStack {
                Label("Parking (\(parkingCount) visit\(parkingCount == 1 ? "" : "s"))", systemImage: "car.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(parkingSavings, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.green)
            }
        }

        // Discount rows (only if there's something to show)
        if merchRate > 0 && merchSpend > 0 {
            HStack {
                Label("Merch discount (\(Int(merchRate * 100))%)", systemImage: "bag.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(merchSpend * merchRate, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.green)
            }
        }
        if foodRate > 0 && foodSpend > 0 {
            HStack {
                Label("Dining discount (\(Int(foodRate * 100))%)", systemImage: "fork.knife")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(foodSpend * foodRate, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.green)
            }
        }
        if discountSavings == 0 && (merchRate > 0 || foodRate > 0) {
            Text("Log food & merch in Spending to see discount savings here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Placeholder pricing

    private var disneyPassPricePlaceholder: String {
        switch appState.disneyPassTier {
        case .incredi:   return "e.g. $1,399"
        case .sorcerer:  return "e.g. $1,099"
        case .pirate:    return "e.g. $769"
        case .pixieDust: return "e.g. $399"
        case .none:      return ""
        }
    }

    private var universalPassPricePlaceholder: String {
        switch appState.universalPassTier {
        case .premier:   return "e.g. $769"
        case .preferred: return "e.g. $499"
        case .power:     return "e.g. $309"
        case .select:    return "e.g. $229"
        case .seasonal:  return "e.g. $149"
        case .none:      return ""
        }
    }
}

// MARK: - Inline currency text field

private struct CurrencyField: View {
    let value: Double
    let placeholder: String
    let onChange: (Double) -> Void

    @State private var text: String

    init(value: Double, placeholder: String, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.placeholder = placeholder
        self.onChange = onChange
        _text = State(initialValue: value > 0 ? String(format: "%.0f", value) : "")
    }

    var body: some View {
        HStack(spacing: 2) {
            Text("$").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .onChange(of: text) { _, new in
                    if let v = Double(new) { onChange(v) }
                    else if new.isEmpty { onChange(0) }
                }
        }
    }
}

// MARK: - Add Visit Saving Sheet

struct AddVisitSavingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    enum ParkingChoice: String, CaseIterable {
        case none = "None"
        case standard = "Standard"
        case valet = "Valet"
    }

    @State private var date = Date()
    @State private var gateValueText = ""
    @State private var note = ""
    @State private var selectedResort: ParkGroup = .disney
    @State private var disneyPark: DisneyPark = .magicKingdom
    @State private var universalPark: UniversalPark = .epicUniverse
    @State private var parking: ParkingChoice = .none
    @State private var parkingValueText = ""

    /// Typical posted rates as editable prefills — verify against the lot that day
    private var defaultParkingPrice: Double {
        switch (selectedResort, parking) {
        case (_, .none):               return 0
        case (.disney, .standard):     return 30
        case (.disney, .valet):        return 75
        case (.universal, .standard):  return 35
        case (.universal, .valet):     return 85
        }
    }

    private var parkingValue: Double { parking == .none ? 0 : (Double(parkingValueText) ?? 0) }

    private var lookupPrice: Double? {
        switch selectedResort {
        case .disney:
            return TicketPriceService.disneyPrice(for: date, park: disneyPark)
        case .universal:
            if let p = TicketPriceService.universalPrice(for: date, park: universalPark) {
                return p  // exact from table
            }
            // Volcano Bay has no data after Oct 25 2026 — return nil so user enters manually
            if universalPark == .volcanoBay { return nil }
            return TicketPriceService.universalEstimate(for: date)
        }
    }

    private var priceFooter: String {
        switch selectedResort {
        case .disney:
            if lookupPrice != nil {
                return "Official gate price. Edit if needed."
            } else {
                return "No price on file for this date. Enter manually or verify on the official site."
            }
        case .universal:
            if TicketPriceService.universalPrice(for: date, park: universalPark) != nil {
                return "Official gate price. Edit if needed."
            } else if universalPark == .volcanoBay {
                return "No Volcano Bay price on file for this date. Enter manually."
            } else {
                return "Estimated — price table only covers through end of 2026. Verify on the official site."
            }
        }
    }

    private var gateValue: Double { Double(gateValueText) ?? 0 }

    private var officialURL: URL {
        selectedResort == .disney
            ? TicketPriceService.disneyTicketURL
            : TicketPriceService.universalTicketURL
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resort") {
                    Picker("Resort", selection: $selectedResort) {
                        ForEach(ParkGroup.allCases) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: selectedResort) { _, _ in
                        applyPrice()
                        applyParkingPrice()
                    }
                }

                Section("Visit Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .onChange(of: date) { _, _ in applyPrice() }
                }

                if selectedResort == .disney {
                    Section("Park") {
                        Picker("Park", selection: $disneyPark) {
                            ForEach(DisneyPark.allCases) { park in
                                Text(park.rawValue).tag(park)
                            }
                        }
                        .onChange(of: disneyPark) { _, _ in applyPrice() }
                    }
                } else {
                    Section("Park") {
                        Picker("Park", selection: $universalPark) {
                            ForEach(UniversalPark.allCases) { park in
                                Text(park.rawValue).tag(park)
                            }
                        }
                        .onChange(of: universalPark) { _, _ in applyPrice() }
                    }
                }

                Section {
                    HStack {
                        Text("$")
                        TextField("0", text: $gateValueText)
                            .keyboardType(.decimalPad)
                    }
                    Link(destination: officialURL) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Verify on official site")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption)
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                } header: {
                    Text("Gate Ticket Value")
                } footer: {
                    Text(priceFooter).font(.caption)
                }

                Section {
                    Picker("Parking", selection: $parking) {
                        ForEach(ParkingChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: parking) { _, _ in applyParkingPrice() }
                    if parking != .none {
                        HStack {
                            Text("$")
                            TextField("0", text: $parkingValueText)
                                .keyboardType(.decimalPad)
                        }
                    }
                } header: {
                    Text("Parking Covered by Pass")
                } footer: {
                    Text(parking == .none
                        ? "If your pass covered parking this visit, pick the type you'd have paid for."
                        : "Typical rate prefilled — edit to match the posted price that day.")
                        .font(.caption)
                }

                Section("Note (optional)") {
                    TextField("e.g. Magic Kingdom day", text: $note)
                }
            }
            .navigationTitle("Log Visit Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saving = VisitSaving(
                            date: date,
                            resort: selectedResort.rawValue,
                            gateValue: gateValue,
                            note: note.isEmpty
                                ? (selectedResort == .disney ? disneyPark.rawValue : universalPark.rawValue)
                                : note,
                            parkingValue: parkingValue,
                            parkingType: parking == .none ? "" : parking.rawValue
                        )
                        modelContext.insert(saving)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(gateValue <= 0 && parkingValue <= 0)
                }
            }
            .onAppear {
                selectedResort = appState.selectedResort
                applyPrice()
            }
        }
    }

    private func applyPrice() {
        if let p = lookupPrice {
            gateValueText = String(format: "%.0f", p)
        } else {
            gateValueText = ""
        }
    }

    private func applyParkingPrice() {
        parkingValueText = parking == .none ? "" : String(format: "%.0f", defaultParkingPrice)
    }
}
