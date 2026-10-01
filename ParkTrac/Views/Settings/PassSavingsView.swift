import SwiftUI
import SwiftData

/// "Your pass costs $9.40 per visit so far" — the pass price amortized across how many times
/// it's actually been used this year (each logged `VisitSaving` is one park entry it covered).
enum PassSavingsCalculator {
    static func costPerVisit(passCost: Double, visits: Int) -> Double? {
        guard passCost > 0, visits > 0 else { return nil }
        return passCost / Double(visits)
    }

    /// Visits still needed to fully recover the pass cost, extrapolating from the average savings
    /// per visit so far. nil once already broken even, or without enough data (no visits, or no
    /// savings yet) to extrapolate from.
    static func visitsToBreakEven(passCost: Double, totalSavings: Double, visits: Int) -> Int? {
        guard passCost > totalSavings, visits > 0 else { return nil }
        let avgPerVisit = totalSavings / Double(visits)
        guard avgPerVisit > 0 else { return nil }
        return Int(((passCost - totalSavings) / avgPerVisit).rounded(.up))
    }
}

/// Pass-period bookkeeping: tapping "I Renewed" snapshots the ending period's cost into a
/// `PassPeriod` row, and `AppState`'s cost/expiry/tier fields move on to represent the new,
/// still-open period. Lifetime numbers (below) are unaffected by renewing; "this pass year"
/// numbers reset to start counting from the renewal date.
enum PassPeriodStats {
    /// The current (ongoing) period's start for a resort — the end of its most recent past
    /// period, or nil with no renewal history yet (lifetime and this-period are then identical).
    static func currentPeriodStart(pastPeriods: [(resort: String, endDate: Date)], resort: String) -> Date? {
        pastPeriods.filter { $0.resort == resort }.map(\.endDate).max()
    }

    /// Every pass ever paid for this resort — past periods' costs plus the current, still-open one.
    static func lifetimeCost(pastPeriods: [(resort: String, cost: Double)], resort: String, currentCost: Double) -> Double {
        pastPeriods.filter { $0.resort == resort }.map(\.cost).reduce(0, +) + currentCost
    }
}

/// Everything `savingsSummaryCard` needs for one resort, one scope (lifetime or this pass year).
private struct PassScopeNumbers {
    let visitSavings: Double
    let parkingSavings: Double
    let parkingCount: Int
    let merchSpend: Double
    let foodSpend: Double
    let discountSavings: Double
    let totalSavings: Double
    let visitCount: Int
}

struct PassSavingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VisitSaving.date, order: .reverse) private var allSavings: [VisitSaving]
    @Query(sort: \PurchaseLog.date, order: .reverse) private var allPurchases: [PurchaseLog]
    @Query private var pastPeriods: [PassPeriod]

    @State private var showAddVisit = false
    @State private var editingDisneyCost = false
    @State private var editingUniversalCost = false
    @State private var showRenewDisney = false
    @State private var showRenewUniversal = false

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

    // MARK: - Pass periods

    private var pastPeriodEndDates: [(resort: String, endDate: Date)] {
        pastPeriods.map { (resort: $0.resort, endDate: $0.endDate) }
    }
    private var pastPeriodCosts: [(resort: String, cost: Double)] {
        pastPeriods.map { (resort: $0.resort, cost: $0.cost) }
    }

    /// nil = no renewal history yet, so "this pass year" and "lifetime" are the same thing.
    private func periodStart(_ resort: ParkGroup) -> Date? {
        PassPeriodStats.currentPeriodStart(pastPeriods: pastPeriodEndDates, resort: resort.rawValue)
    }

    private func lifetimeCost(_ resort: ParkGroup, currentCost: Double) -> Double {
        PassPeriodStats.lifetimeCost(pastPeriods: pastPeriodCosts, resort: resort.rawValue, currentCost: currentCost)
    }

    // MARK: - Savings calculations

    /// `since` nil = lifetime; otherwise only visits/purchases on or after that date (this pass year).
    private func numbers(resort: ParkGroup, since: Date?, merchRate: Double, foodRate: Double) -> PassScopeNumbers {
        func inScope(_ entryResort: String, _ date: Date) -> Bool {
            guard entryResort == resort.rawValue else { return false }
            guard let since else { return true }
            return date >= since
        }
        let savings = allSavings.filter { inScope($0.resort, $0.date) }
        let purchases = allPurchases.filter { inScope($0.resort, $0.date) }
        let visitSavings = savings.map(\.gateValue).reduce(0, +)
        let parkingSavings = savings.map(\.parkingValue).reduce(0, +)
        let parkingCount = savings.filter { $0.parkingValue > 0 }.count
        // Only purchases marked AP eligible count toward discount savings.
        let merchSpend = purchases.filter { $0.category == "Merchandise" && $0.isAPEligible }.map(\.amount).reduce(0, +)
        let foodSpend = purchases.filter { $0.category == "Food" && $0.isAPEligible }.map(\.amount).reduce(0, +)
        // Amounts entered are post-discount (what the user actually paid):
        // to recover the original discount amount, savings = paid × rate / (1 − rate).
        let merch = merchRate > 0 ? merchSpend * merchRate / (1 - merchRate) : 0
        let food = foodRate > 0 ? foodSpend * foodRate / (1 - foodRate) : 0
        let discountSavings = merch + food
        return PassScopeNumbers(visitSavings: visitSavings, parkingSavings: parkingSavings, parkingCount: parkingCount,
                                merchSpend: merchSpend, foodSpend: foodSpend, discountSavings: discountSavings,
                                totalSavings: visitSavings + parkingSavings + discountSavings, visitCount: savings.count)
    }

    // MARK: - Body

    var body: some View {
        Form {
            // Pass cost entry
            if appState.disneyPassTier != .none {
                Section {
                    passCostRow(
                        label: appState.disneyPassTier.rawValue,
                        cost: appState.disneyPassCost,
                        placeholder: disneyPassPricePlaceholder,
                        onChange: { appState.disneyPassCost = $0 }
                    )
                    Button("I Renewed") { showRenewDisney = true }
                } header: {
                    Text("Disney Pass Cost")
                } footer: {
                    if let start = periodStart(.disney) {
                        Text("This pass year started \(start.formatted(date: .abbreviated, time: .omitted)).")
                    }
                }
            }

            if appState.universalPassTier != .none {
                Section {
                    passCostRow(
                        label: appState.universalPassTier.rawValue,
                        cost: appState.universalPassCost,
                        placeholder: universalPassPricePlaceholder,
                        onChange: { appState.universalPassCost = $0 }
                    )
                    Button("I Renewed") { showRenewUniversal = true }
                } header: {
                    Text("Universal Pass Cost")
                } footer: {
                    if let start = periodStart(.universal) {
                        Text("This pass year started \(start.formatted(date: .abbreviated, time: .omitted)).")
                    }
                }
            }

            // Disney summary — this pass year, then lifetime
            if appState.disneyPassTier != .none {
                let thisYear = numbers(resort: .disney, since: periodStart(.disney),
                                       merchRate: disneyMerchRate, foodRate: disneyFoodRate)
                Section {
                    savingsSummaryCard(resort: ParkGroup.disney.rawValue, passCost: appState.disneyPassCost,
                                       net: thisYear.totalSavings - appState.disneyPassCost,
                                       merchRate: disneyMerchRate, foodRate: disneyFoodRate, numbers: thisYear)
                } header: {
                    Text("Disney Savings — This Pass Year")
                }

                if periodStart(.disney) != nil {
                    let lifetime = numbers(resort: .disney, since: nil, merchRate: disneyMerchRate, foodRate: disneyFoodRate)
                    let cost = lifetimeCost(.disney, currentCost: appState.disneyPassCost)
                    Section {
                        savingsSummaryCard(resort: ParkGroup.disney.rawValue, passCost: cost,
                                           net: lifetime.totalSavings - cost,
                                           merchRate: disneyMerchRate, foodRate: disneyFoodRate, numbers: lifetime)
                    } header: {
                        Text("Disney Savings — Lifetime")
                    } footer: {
                        Text("Every Disney pass you've paid for, vs. every visit you've ever logged.")
                    }
                }
            }

            // Universal summary — this pass year, then lifetime
            if appState.universalPassTier != .none {
                let thisYear = numbers(resort: .universal, since: periodStart(.universal),
                                       merchRate: universalMerchRate, foodRate: universalFoodRate)
                Section {
                    savingsSummaryCard(resort: ParkGroup.universal.rawValue, passCost: appState.universalPassCost,
                                       net: thisYear.totalSavings - appState.universalPassCost,
                                       merchRate: universalMerchRate, foodRate: universalFoodRate, numbers: thisYear)
                } header: {
                    Text("Universal Savings — This Pass Year")
                }

                if periodStart(.universal) != nil {
                    let lifetime = numbers(resort: .universal, since: nil, merchRate: universalMerchRate, foodRate: universalFoodRate)
                    let cost = lifetimeCost(.universal, currentCost: appState.universalPassCost)
                    Section {
                        savingsSummaryCard(resort: ParkGroup.universal.rawValue, passCost: cost,
                                           net: lifetime.totalSavings - cost,
                                           merchRate: universalMerchRate, foodRate: universalFoodRate, numbers: lifetime)
                    } header: {
                        Text("Universal Savings — Lifetime")
                    } footer: {
                        Text("Every Universal pass you've paid for, vs. every visit you've ever logged.")
                    }
                }
            }

            // Visit log
            Section {
                Button {
                    showAddVisit = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Log a Visit").fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.green)

                if allSavings.isEmpty {
                    Text("Log your first visit to track gate ticket and parking savings.")
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
                    .accessibilityLabel("Log a visit")
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
        .sheet(isPresented: $showRenewDisney) {
            RenewPassSheet(resortLabel: "Disney", tierOptions: DisneyPassTier.allCases.map(\.rawValue),
                          currentTierRaw: appState.disneyPassTier.rawValue, oldCost: appState.disneyPassCost,
                          oldExpiry: appState.disneyPassExpiry) { newCost, newExpiry, newTierRaw in
                renew(.disney, newCost: newCost, newExpiry: newExpiry, newTierRaw: newTierRaw)
            }
        }
        .sheet(isPresented: $showRenewUniversal) {
            RenewPassSheet(resortLabel: "Universal", tierOptions: UniversalPassTier.allCases.map(\.rawValue),
                          currentTierRaw: appState.universalPassTier.rawValue, oldCost: appState.universalPassCost,
                          oldExpiry: appState.universalPassExpiry) { newCost, newExpiry, newTierRaw in
                renew(.universal, newCost: newCost, newExpiry: newExpiry, newTierRaw: newTierRaw)
            }
        }
    }

    /// Snapshots the ending period into a `PassPeriod`, then moves `AppState`'s fields on to the
    /// new one and reschedules the 30-day renewal reminder.
    private func renew(_ resort: ParkGroup, newCost: Double, newExpiry: Date, newTierRaw: String) {
        let oldCost = resort == .disney ? appState.disneyPassCost : appState.universalPassCost
        let oldTierRaw = resort == .disney ? appState.disneyPassTier.rawValue : appState.universalPassTier.rawValue
        let earliestVisit = allSavings.filter { $0.resort == resort.rawValue }.map(\.date).min()
        let start = periodStart(resort) ?? earliestVisit ?? .now
        modelContext.insert(PassPeriod(resort: resort.rawValue, tier: oldTierRaw, cost: oldCost, startDate: start, endDate: .now))
        try? modelContext.save()

        switch resort {
        case .disney:
            appState.disneyPassCost = newCost
            appState.disneyPassExpiry = newExpiry
            if let tier = DisneyPassTier(rawValue: newTierRaw) { appState.disneyPassTier = tier }
        case .universal:
            appState.universalPassCost = newCost
            appState.universalPassExpiry = newExpiry
            if let tier = UniversalPassTier(rawValue: newTierRaw) { appState.universalPassTier = tier }
        default:
            break
        }
        if let reminderDate = Calendar.current.date(byAdding: .day, value: -30, to: newExpiry) {
            NotificationService.shared.schedulePassRenewalReminder(resort: resort.rawValue, passName: newTierRaw, date: reminderDate)
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
        passCost: Double,
        net: Double,
        merchRate: Double,
        foodRate: Double,
        numbers: PassScopeNumbers
    ) -> some View {
        let visitSavings = numbers.visitSavings
        let parkingSavings = numbers.parkingSavings
        let parkingCount = numbers.parkingCount
        let discountSavings = numbers.discountSavings
        let totalSavings = numbers.totalSavings
        let visitCount = numbers.visitCount
        let merchSpend = numbers.merchSpend
        let foodSpend = numbers.foodSpend
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

        if let perVisit = PassSavingsCalculator.costPerVisit(passCost: passCost, visits: visitCount) {
            HStack {
                Label("Cost per visit", systemImage: "divide.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(perVisit, format: .currency(code: "USD"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }

        if let visitsLeft = PassSavingsCalculator.visitsToBreakEven(passCost: passCost, totalSavings: totalSavings, visits: visitCount) {
            HStack {
                Label("To break even", systemImage: "flag.checkered")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("~\(visitsLeft) more visit\(visitsLeft == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
        default:                       return 0   // annual passes are Orlando-only
        }
    }

    private var parkingValue: Double { parking == .none ? 0 : (Double(parkingValueText) ?? 0) }

    private var lookupPrice: Double? {
        switch selectedResort {
        case .disney:
            return TicketPriceService.disneyPrice(for: date, park: disneyPark)
        case .tokyoDisney, .universalJapan:
            return nil
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
        case .tokyoDisney, .universalJapan:
            return "Enter the ticket value manually."
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
                        ForEach(ParkGroup.orlando) { group in
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
