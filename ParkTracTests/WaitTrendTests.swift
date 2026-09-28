import XCTest
@testable import ParkTrac

/// Rising/falling arrow on ride cards, momentum since the last refresh only.
final class WaitTrendTests: XCTestCase {
    func testRisingWhenWaitClimbsPastThreshold() {
        XCTAssertEqual(WaitTrend.compute(previous: 30, current: 40), .rising)
    }

    func testFallingWhenWaitDropsPastThreshold() {
        XCTAssertEqual(WaitTrend.compute(previous: 40, current: 30), .falling)
    }

    func testNoTrendBelowThreshold() {
        XCTAssertNil(WaitTrend.compute(previous: 30, current: 32))
        XCTAssertNil(WaitTrend.compute(previous: 30, current: 28))
    }

    func testNoTrendWithoutAPreviousReading() {
        XCTAssertNil(WaitTrend.compute(previous: nil, current: 40))
    }

    func testCustomThreshold() {
        XCTAssertNil(WaitTrend.compute(previous: 30, current: 38, threshold: 10))
        XCTAssertEqual(WaitTrend.compute(previous: 30, current: 41, threshold: 10), .rising)
    }
}
