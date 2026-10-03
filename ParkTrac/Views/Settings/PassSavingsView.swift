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

    /// How much the pass has cost across every renewal — "$769 → $999 over 3 renewals (+30%)".
    /// nil with no renewal history yet (nothing to trend).
    static func costTrend(pastPeriods: [(resort: String, cost: Double, startDate: Date)], resort: String, currentCost: Double) -> PassCostTrend? {
        let periods = pastPeriods.filter { $0.resort == resort }.sorted { $0.startDate < $1.startDate }
        guard let first = periods.first else { return nil }
        return PassCostTrend(firstCost: first.cost, currentCost: currentCost, renewalCount: periods.count)
    }

    /// Which pass year (past periods, plus the current still-open one) had the best ROI —
    /// "your best pass year" — once there are at least 2 years to compare. `years` only needs
    /// gate/parking savings, not the discount-rate math (a looser, best-effort fun stat, same
    /// spirit as `DayRecap.costPerRide`), since a past period's tier-specific discount rate
    /// isn't worth re-deriving here.
    static func bestPassYear(years: [PassYear], resort: String) -> PassYear? {
        let matches = years.filter { $0.resort == resort }
        guard matches.count >= 2 else { return nil }
        return matches.max { $0.netSavings < $1.netSavings }
    }

    /// Cost per visit for each pass year (past periods plus the current one), chronological —
    /// nil entries are years with no logged visits (yet). nil overall with fewer than 2 years.
    static func costPerVisitTrend(years: [(startDate: Date, cost: Double, visitCount: Int)]) -> [Double?]? {
        guard years.count >= 2 else { return nil }
        return years.sorted { $0.startDate < $1.startDate }
            .map { PassSavingsCalculator.costPerVisit(passCost: $0.cost, visits: $0.visitCount) }
    }

    /// "$192 → $90 → $64" for display, skipping years with no visits yet.
    static func costPerVisitTrendText(_ trend: [Double?]) -> String {
        trend.map { perVisit in perVisit.map { String(format: "$%.0f", $0) } ?? "–" }
            .joined(separator: " → ")
    }
}

struct PassCostTrend: Equatable {
    let firstCost: Double
    let currentCost: Double
    let renewalCount: Int
    var percentChange: Double? {
        guard firstCost > 0 else { return nil }
        return (currentCost - firstCost) / firstCost * 100
    }
}

struct PassYear: Equatable {
    let resort: String
    let tier: String
    let startDate: Date
    let endDate: Date?       // nil = still open (the current year)
    let cost: Double
    let visitCount: Int
    let netSavings: Double
}

/// Discount rates by tier (not just the currently-selected one) — needed both by
/// `PassSavingsView`'s own tier and by `PassUpgradeAdvisor`'s "what if I upgraded" comparison.
/// Source: Official Disney/Universal passholder discount pages (verified May 2026).
enum PassDiscountRates {
    /// All Disney AP tiers receive the same discount rates.
    static func disneyMerchRate(_ tier: DisneyPassTier) -> Double { tier != .none ? 0.20 : 0 }
    static func disneyFoodRate(_ tier: DisneyPassTier) -> Double { tier != .none ? 0.10 : 0 }

    /// Universal rates vary by tier.
    static func universalMerchRate(_ tier: UniversalPassTier) -> Double {
        switch tier {
        case .premier:              return 0.15
        case .preferred:            return 0.10
        case .power, .select, .seasonal, .none: return 0
        }
    }
    static func universalFoodRate(_ tier: UniversalPassTier) -> Double {
        switch tier {
        case .premier:              return 0.15
        case .preferred:            return 0.10
        case .power, .select, .seasonal, .none: return 0
        }
    }

    /// Typical sticker price for a tier, same figures as the cost field's placeholder text —
    /// used as a reference "what the next tier up usually costs" starting point for the
    /// upgrade advisor (the guest can still type in their own actual price).
    static func referencePrice(_ tier: DisneyPassTier) -> Double? {
        switch tier {
        case .incredi:   return 1399
        case .sorcerer:  return 1099
        case .pirate:    return 769
        case .pixieDust: return 399
        case .none:      return nil
        }
    }
    static func referencePrice(_ tier: UniversalPassTier) -> Double? {
        switch tier {
        case .premier:   return 769
        case .preferred: return 499
        case .power:     return 309
        case .select:    return 229
        case .seasonal:  return 149
        case .none:      return nil
        }
    }
}

/// Whether upgrading to the next tier up would be worth it, purely on discount-rate math — this
/// doesn't account for blockout-date access, which is the other real reason to upgrade and isn't
/// quantifiable from data this app has.
enum PassUpgradeAdvisor {
    struct Comparison: Equatable {
        let costDifference: Double        // upgradeCost − currentCost (positive = upgrade costs more)
        let extraDiscountSavings: Double  // discount savings at upgrade rates − at current rates, from spend so far
        var netDifference: Double { costDifference - extraDiscountSavings }
    }

    static func compare(currentCost: Double, upgradeCost: Double, merchSpend: Double, foodSpend: Double,
                        currentMerchRate: Double, currentFoodRate: Double,
                        upgradeMerchRate: Double, upgradeFoodRate: Double) -> Comparison {
        func discountSavings(merchRate: Double, foodRate: Double) -> Double {
            let merch = merchRate > 0 ? merchSpend * merchRate / (1 - merchRate) : 0
            let food = foodRate > 0 ? foodSpend * foodRate / (1 - foodRate) : 0
            return merch + food
        }
        let extra = discountSavings(merchRate: upgradeMerchRate, foodRate: upgradeFoodRate)
            - discountSavings(merchRate: currentMerchRate, foodRate: currentFoodRate)
        return Comparison(costDifference: upgradeCost - currentCost, extraDiscountSavings: extra)
    }

    /// The next tier up in each ladder, or nil already at the top.
    static func nextTier(_ tier: DisneyPassTier) -> DisneyPassTier? {
        let tiers = DisneyPassTier.allCases.filter { $0 != .none }
        guard let idx = tiers.firstIndex(of: tier), idx + 1 < tiers.count else { return nil }
        return tiers[idx + 1]
    }
    static func nextTier(_ tier: UniversalPassTier) -> UniversalPassTier? {
        let tiers = UniversalPassTier.allCases.filter { $0 != .none }
        guard let idx = tiers.firstIndex(of: tier), idx + 1 < tiers.count else { return nil }
        return tiers[idx + 1]
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

    private var disneyMerchRate: Double { PassDiscountRates.disneyMerchRate(appState.disneyPassTier) }
    private var disneyFoodRate:  Double { PassDiscountRates.disneyFoodRate(appState.disneyPassTier) }
    private var universalMerchRate: Double { PassDiscountRates.universalMerchRate(appState.universalPassTier) }
    private var universalFoodRate: Double { PassDiscountRates.universalFoodRate(appState.universalPassTier) }

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

    private func costTrend(_ resort: ParkGroup, currentCost: Double) -> PassCostTrend? {
        let periods = pastPeriods.filter { $0.resort == resort.rawValue }
            .map { (resort: $0.resort, cost: $0.cost, startDate: $0.startDate) }
        return PassPeriodStats.costTrend(pastPeriods: periods, resort: resort.rawValue, currentCost: currentCost)
    }

    /// Gate ticket + parking savings logged within a date range (the discount-free basis for `PassYear`).
    private func visitSavingsNet(resort: ParkGroup, from: Date, to: Date) -> Double {
        savingsInRange(resort: resort, from: from, to: to).map { $0.gateValue + $0.parkingValue }.reduce(0, +)
    }

    private func visitCount(resort: ParkGroup, from: Date, to: Date) -> Int {
        savingsInRange(resort: resort, from: from, to: to).count
    }

    private func savingsInRange(resort: ParkGroup, from: Date, to: Date) -> [VisitSaving] {
        allSavings.filter { $0.resort == resort.rawValue && $0.date >= from && $0.date < to }
    }

    private func passYears(_ resort: ParkGroup, currentTierRaw: String, currentCost: Double) -> [PassYear] {
        let past = pastPeriods.filter { $0.resort == resort.rawValue }.map { period -> PassYear in
            let visits = visitCount(resort: resort, from: period.startDate, to: period.endDate)
            let net = visitSavingsNet(resort: resort, from: period.startDate, to: period.endDate) - period.cost
            return PassYear(resort: resort.rawValue, tier: period.tier, startDate: period.startDate, endDate: period.endDate,
                            cost: period.cost, visitCount: visits, netSavings: net)
        }
        let currentStart = periodStart(resort) ?? past.map(\.startDate).min() ?? .distantPast
        let currentVisits = visitCount(resort: resort, from: currentStart, to: .distantFuture)
        let currentNet = visitSavingsNet(resort: resort, from: currentStart, to: .distantFuture) - currentCost
        let currentYear = PassYear(resort: resort.rawValue, tier: currentTierRaw, startDate: currentStart, endDate: nil,
                                   cost: currentCost, visitCount: currentVisits, netSavings: currentNet)
        return past + [currentYear]
    }

    private func bestPassYear(_ resort: ParkGroup, currentTierRaw: String, currentCost: Double) -> PassYear? {
        PassPeriodStats.bestPassYear(years: passYears(resort, currentTierRaw: currentTierRaw, currentCost: currentCost), resort: resort.rawValue)
    }

    private func costPerVisitTrend(_ resort: ParkGroup, currentTierRaw: String, currentCost: Double) -> [Double?]? {
        let years = passYears(resort, currentTierRaw: currentTierRaw, currentCost: currentCost)
            .map { (startDate: $0.startDate, cost: $0.cost, visitCount: $0.visitCount) }
        return PassPeriodStats.costPerVisitTrend(years: years)
    }

    /// Discount-free financial comparison against the next tier up, from this pass year's spend
    /// so far. nil already at the top tier.
    private func upgradeComparison(_ resort: ParkGroup, currentTierRaw: String, currentCost: Double) -> (nextTierName: String, comparison: PassUpgradeAdvisor.Comparison)? {
        let thisYear = numbers(resort: resort, since: periodStart(resort),
                               merchRate: resort == .disney ? disneyMerchRate : universalMerchRate,
                               foodRate: resort == .disney ? disneyFoodRate : universalFoodRate)
        switch resort {
        case .disney:
            guard let next = PassUpgradeAdvisor.nextTier(appState.disneyPassTier) else { return nil }
            let upgradeCost = PassDiscountRates.referencePrice(next) ?? currentCost
            let comparison = PassUpgradeAdvisor.compare(
                currentCost: currentCost, upgradeCost: upgradeCost, merchSpend: thisYear.merchSpend, foodSpend: thisYear.foodSpend,
                currentMerchRate: disneyMerchRate, currentFoodRate: disneyFoodRate,
                upgradeMerchRate: PassDiscountRates.disneyMerchRate(next), upgradeFoodRate: PassDiscountRates.disneyFoodRate(next))
            return (next.rawValue, comparison)
        case .universal:
            guard let next = PassUpgradeAdvisor.nextTier(appState.universalPassTier) else { return nil }
            let upgradeCost = PassDiscountRates.referencePrice(next) ?? currentCost
            let comparison = PassUpgradeAdvisor.compare(
                currentCost: currentCost, upgradeCost: upgradeCost, merchSpend: thisYear.merchSpend, foodSpend: thisYear.foodSpend,
                currentMerchRate: universalMerchRate, currentFoodRate: universalFoodRate,
                upgradeMerchRate: PassDiscountRates.universalMerchRate(next), upgradeFoodRate: PassDiscountRates.universalFoodRate(next))
            return (next.rawValue, comparison)
        default:
            return nil
        }
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
                .onAppear { checkPennyPincher(passCost: appState.disneyPassCost, net: thisYear.totalSavings - appState.disneyPassCost) }

                upgradeSection(.disney, currentTierRaw: appState.disneyPassTier.rawValue, currentCost: appState.disneyPassCost)

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
                    .onAppear { checkPennyPincher(passCost: cost, net: lifetime.totalSavings - cost) }
                    passHistorySection(.disney, label: "Disney", currentTierRaw: appState.disneyPassTier.rawValue,
                                      currentCost: appState.disneyPassCost)
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
                .onAppear { checkPennyPincher(passCost: appState.universalPassCost, net: thisYear.totalSavings - appState.universalPassCost) }

                upgradeSection(.universal, currentTierRaw: appState.universalPassTier.rawValue, currentCost: appState.universalPassCost)

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
                    .onAppear { checkPennyPincher(passCost: cost, net: lifetime.totalSavings - cost) }
                    passHistorySection(.universal, label: "Universal", currentTierRaw: appState.universalPassTier.rawValue,
                                      currentCost: appState.universalPassCost)
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

    /// Marks the Penny Pincher badge earned the moment a scope's net savings cover its cost —
    /// once marked it's never unmarked (see `PennyPincher`'s doc comment).
    private func checkPennyPincher(passCost: Double, net: Double) {
        guard passCost > 0, net >= 0 else { return }
        PennyPincher.markBrokeEven()
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

    /// "Pass cost trend" and "Your best pass year" — shown only once there's renewal history to
    /// compare (same gate as the Lifetime section above, which this sits right after).
    @ViewBuilder
    private func passHistorySection(_ resort: ParkGroup, label: String, currentTierRaw: String, currentCost: Double) -> some View {
        if let trend = costTrend(resort, currentCost: currentCost) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Pass cost trend", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(trend.firstCost, format: .currency(code: "USD")) → \(trend.currentCost, format: .currency(code: "USD"))")
                        .font(.caption.weight(.semibold))
                }
                if let pct = trend.percentChange {
                    Text("Over \(trend.renewalCount) renewal\(trend.renewalCount == 1 ? "" : "s") — \(pct >= 0 ? "+" : "")\(Int(pct.rounded()))%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        if let best = bestPassYear(resort, currentTierRaw: currentTierRaw, currentCost: currentCost) {
            HStack {
                Label("Best \(label) pass year", systemImage: "trophy.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(best.netSavings, format: .currency(code: "USD")).font(.caption.weight(.semibold)).foregroundStyle(.green)
                    Text(best.startDate, format: .dateTime.month(.abbreviated).year()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        if let trend = costPerVisitTrend(resort, currentTierRaw: currentTierRaw, currentCost: currentCost) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Cost per visit, year over year", systemImage: "chart.xyaxis.line")
                    .font(.caption).foregroundStyle(.secondary)
                Text(PassPeriodStats.costPerVisitTrendText(trend))
                    .font(.caption.weight(.semibold))
            }
            .padding(.vertical, 2)
        }
    }

    /// Whether the next tier up would be worth it, purely on discount-rate math from this pass
    /// year's spend so far. Always shown (not gated on renewal history) when a next tier exists.
    @ViewBuilder
    private func upgradeSection(_ resort: ParkGroup, currentTierRaw: String, currentCost: Double) -> some View {
        if let result = upgradeComparison(resort, currentTierRaw: currentTierRaw, currentCost: currentCost) {
            let nextTierName = result.nextTierName
            let comparison = result.comparison
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upgrading to \(nextTierName) would cost \(comparison.costDifference, format: .currency(code: "USD")) more\(comparison.extraDiscountSavings > 0 ? ", offset by \(comparison.extraDiscountSavings, format: .currency(code: "USD")) in extra discounts so far" : "")")
                        .font(.subheadline)
                    Text(comparison.netDifference <= 0
                        ? "Already worth it on discounts alone this pass year."
                        : "Net \(abs(comparison.netDifference), format: .currency(code: "USD")) more out of pocket so far — the other reason to upgrade is blockout-date access, which this doesn't account for.")
                        .font(.caption)
                        .foregroundStyle(comparison.netDifference <= 0 ? .green : .secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Should I Upgrade?")
            }
        }
    }

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

    private static func pricePlaceholder(_ price: Double?) -> String {
        guard let price else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "e.g. $\(formatter.string(from: price as NSNumber) ?? "\(Int(price))")"
    }

    private var disneyPassPricePlaceholder: String {
        Self.pricePlaceholder(PassDiscountRates.referencePrice(appState.disneyPassTier))
    }

    private var universalPassPricePlaceholder: String {
        Self.pricePlaceholder(PassDiscountRates.referencePrice(appState.universalPassTier))
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
