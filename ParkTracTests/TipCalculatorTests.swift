import XCTest
@testable import ParkTrac

final class TipCalculatorTests: XCTestCase {
    func testTipAndTotal() {
        let calc = TipCalculator(bill: 100, tipPercent: 20, people: 1)
        XCTAssertEqual(calc.tipAmount, 20)
        XCTAssertEqual(calc.total, 120)
        XCTAssertEqual(calc.perPerson, 120)
    }

    func testSplitAcrossPeople() {
        let calc = TipCalculator(bill: 90, tipPercent: 20, people: 3)
        XCTAssertEqual(calc.total, 108)
        XCTAssertEqual(calc.perPerson, 36)
    }

    func testZeroPeopleFallsBackToTotal() {
        let calc = TipCalculator(bill: 50, tipPercent: 15, people: 0)
        XCTAssertEqual(calc.perPerson, calc.total)
    }
}
