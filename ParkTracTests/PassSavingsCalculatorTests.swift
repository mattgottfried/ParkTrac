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
}
