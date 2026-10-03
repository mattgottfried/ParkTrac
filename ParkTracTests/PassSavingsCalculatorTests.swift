import XCTest
@testable import ParkTrac

final class PassSavingsCalculatorTests: XCTestCase {
    func testCostPerVisit() {
        XCTAssertEqual(PassSavingsCalculator.costPerVisit(passCost: 940, visits: 100), 9.4)
        XCTAssertNil(PassSavingsCalculator.costPerVisit(passCost: 0, visits: 5), "no cost entered yet")
        XCTAssertNil(PassSavingsCalculator.costPerVisit(passCost: 940, visits: 0), "no visits logged yet")
    }

    func testVisitsToBreakEvenExtrapolatesFromAverageSoFar() {
        // $100 saved over 4 visits = $25/visit average; $300 left of a $400 pass needs 12 more
        XCTAssertEqual(PassSavingsCalculator.visitsToBreakEven(passCost: 400, totalSavings: 100, visits: 4), 12)
    }

    func testNoBreakEvenCountdownOnceAlreadyPaidOff() {
        XCTAssertNil(PassSavingsCalculator.visitsToBreakEven(passCost: 400, totalSavings: 400, visits: 4))
        XCTAssertNil(PassSavingsCalculator.visitsToBreakEven(passCost: 400, totalSavings: 500, visits: 4))
    }

    func testNoBreakEvenCountdownWithoutEnoughData() {
        XCTAssertNil(PassSavingsCalculator.visitsToBreakEven(passCost: 400, totalSavings: 0, visits: 0))
        XCTAssertNil(PassSavingsCalculator.visitsToBreakEven(passCost: 400, totalSavings: 0, visits: 4), "no savings yet to extrapolate from")
    }

    // MARK: Pass periods (lifetime vs. this pass year)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testCurrentPeriodStartIsTheLatestPastPeriodsEnd() {
        let periods = [(resort: "Walt Disney World", endDate: date(2025, 1, 1)),
                       (resort: "Walt Disney World", endDate: date(2026, 1, 1)),
                       (resort: "Universal Orlando", endDate: date(2024, 6, 1))]
        XCTAssertEqual(PassPeriodStats.currentPeriodStart(pastPeriods: periods, resort: "Walt Disney World"), date(2026, 1, 1))
    }

    func testNoCurrentPeriodStartWithoutRenewalHistory() {
        XCTAssertNil(PassPeriodStats.currentPeriodStart(pastPeriods: [], resort: "Walt Disney World"))
    }

    func testLifetimeCostSumsPastPeriodsPlusCurrent() {
        let periods = [(resort: "Walt Disney World", cost: 800.0), (resort: "Walt Disney World", cost: 900.0),
                       (resort: "Universal Orlando", cost: 500.0)]
        XCTAssertEqual(PassPeriodStats.lifetimeCost(pastPeriods: periods, resort: "Walt Disney World", currentCost: 1000), 2700)
    }

    func testLifetimeCostIsJustCurrentWithNoHistory() {
        XCTAssertEqual(PassPeriodStats.lifetimeCost(pastPeriods: [], resort: "Walt Disney World", currentCost: 1000), 1000)
    }

    // MARK: Pass cost trend

    func testCostTrendComparesFirstEverCostToCurrent() {
        let periods = [(resort: "Walt Disney World", cost: 769.0, startDate: date(2024, 1, 1)),
                       (resort: "Walt Disney World", cost: 899.0, startDate: date(2025, 1, 1))]
        let trend = try! XCTUnwrap(PassPeriodStats.costTrend(pastPeriods: periods, resort: "Walt Disney World", currentCost: 999))
        XCTAssertEqual(trend.firstCost, 769)
        XCTAssertEqual(trend.renewalCount, 2)
        XCTAssertEqual(trend.percentChange.map { ($0 * 10).rounded() / 10 }, 29.9)
    }

    func testNoCostTrendWithoutRenewalHistory() {
        XCTAssertNil(PassPeriodStats.costTrend(pastPeriods: [], resort: "Walt Disney World", currentCost: 999))
    }

    // MARK: Best pass year

    func testBestPassYearPicksTheHighestNetSavings() {
        let years = [
            PassYear(resort: "Walt Disney World", tier: "Pirate Pass", startDate: date(2024, 1, 1), endDate: date(2025, 1, 1), cost: 769, visitCount: 10, netSavings: 200),
            PassYear(resort: "Walt Disney World", tier: "Sorcerer Pass", startDate: date(2025, 1, 1), endDate: nil, cost: 1099, visitCount: 15, netSavings: 450),
        ]
        let best = try! XCTUnwrap(PassPeriodStats.bestPassYear(years: years, resort: "Walt Disney World"))
        XCTAssertEqual(best.tier, "Sorcerer Pass")
        XCTAssertEqual(best.netSavings, 450)
    }

    func testNoBestPassYearWithFewerThanTwoYears() {
        let years = [PassYear(resort: "Walt Disney World", tier: "Pirate Pass", startDate: date(2024, 1, 1), endDate: nil, cost: 769, visitCount: 10, netSavings: 200)]
        XCTAssertNil(PassPeriodStats.bestPassYear(years: years, resort: "Walt Disney World"))
    }

    // MARK: Cost per visit trend

    func testCostPerVisitTrendOverYears() {
        let years: [(startDate: Date, cost: Double, visitCount: Int)] = [
            (startDate: date(2024, 1, 1), cost: 769, visitCount: 4),
            (startDate: date(2025, 1, 1), cost: 1099, visitCount: 20),
        ]
        let trend = try! XCTUnwrap(PassPeriodStats.costPerVisitTrend(years: years))
        XCTAssertEqual(trend, [192.25, 54.95])
        XCTAssertEqual(PassPeriodStats.costPerVisitTrendText(trend), "$192 → $55")
    }

    func testCostPerVisitTrendSkipsYearsWithNoVisits() {
        let years: [(startDate: Date, cost: Double, visitCount: Int)] = [
            (startDate: date(2024, 1, 1), cost: 769, visitCount: 0),
            (startDate: date(2025, 1, 1), cost: 1099, visitCount: 10),
        ]
        let trend = try! XCTUnwrap(PassPeriodStats.costPerVisitTrend(years: years))
        XCTAssertEqual(PassPeriodStats.costPerVisitTrendText(trend), "– → $110")
    }

    func testNoCostPerVisitTrendWithFewerThanTwoYears() {
        XCTAssertNil(PassPeriodStats.costPerVisitTrend(years: [(startDate: date(2024, 1, 1), cost: 769, visitCount: 4)]))
    }

    // MARK: Should I upgrade?

    func testUpgradeAdvisorFindsTheNextTierUp() {
        XCTAssertEqual(PassUpgradeAdvisor.nextTier(DisneyPassTier.pirate), .sorcerer)
        XCTAssertNil(PassUpgradeAdvisor.nextTier(DisneyPassTier.incredi), "already at the top")
        XCTAssertEqual(PassUpgradeAdvisor.nextTier(UniversalPassTier.select), .power)
    }

    func testUpgradeComparisonAccountsForExtraDiscountSavings() {
        // Universal Preferred (10%) -> Premier (15%): $150 more upfront, but 5% more off $1000 of spend saves ~$56
        let comparison = PassUpgradeAdvisor.compare(
            currentCost: 499, upgradeCost: 649, merchSpend: 500, foodSpend: 500,
            currentMerchRate: 0.10, currentFoodRate: 0.10, upgradeMerchRate: 0.15, upgradeFoodRate: 0.15)
        XCTAssertEqual(comparison.costDifference, 150)
        XCTAssertGreaterThan(comparison.extraDiscountSavings, 0)
    }

    func testUpgradeComparisonIsJustCostWhenDiscountRatesMatch() {
        // Disney tiers all share the same merch/food rate, so upgrading only ever costs more.
        let comparison = PassUpgradeAdvisor.compare(
            currentCost: 769, upgradeCost: 1099, merchSpend: 300, foodSpend: 300,
            currentMerchRate: 0.20, currentFoodRate: 0.10, upgradeMerchRate: 0.20, upgradeFoodRate: 0.10)
        XCTAssertEqual(comparison.extraDiscountSavings, 0)
        XCTAssertEqual(comparison.netDifference, 330)
    }
}
