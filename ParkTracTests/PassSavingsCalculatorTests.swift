import XCTest
@testable import ParkTrac

final class PassSavingsCalculatorTests: XCTestCase {
    func testCostPerVisit() {
        XCTAssertEqual(PassSavingsCalculator.costPerVisit(passCost: 940, visits: 100), 9.4)
        XCTAssertNil(PassSavingsCalculator.costPerVisit(passCost: 0, visits: 5), "no cost entered yet")
        XCTAssertNil(PassSavingsCalculator.costPerVisit(passCost: 940, visits: 0), "no visits logged yet")
    }
}
