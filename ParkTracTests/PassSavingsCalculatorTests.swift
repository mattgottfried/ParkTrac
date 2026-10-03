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
            PassYear(resort: "Walt Disney World", tier: "Pirate Pass", startDate: date(2024, 1, 1), endDate: date(2025, 1, 1), netSavings: 200),
            PassYear(resort: "Walt Disney World", tier: "Sorcerer Pass", startDate: date(2025, 1, 1), endDate: nil, netSavings: 450),
        ]
        let best = try! XCTUnwrap(PassPeriodStats.bestPassYear(years: years, resort: "Walt Disney World"))
        XCTAssertEqual(best.tier, "Sorcerer Pass")
        XCTAssertEqual(best.netSavings, 450)
    }

    func testNoBestPassYearWithFewerThanTwoYears() {
        let years = [PassYear(resort: "Walt Disney World", tier: "Pirate Pass", startDate: date(2024, 1, 1), endDate: nil, netSavings: 200)]
        XCTAssertNil(PassPeriodStats.bestPassYear(years: years, resort: "Walt Disney World"))
    }
}
