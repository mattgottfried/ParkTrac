import XCTest
@testable import ParkTrac

/// Mobile order pickup window countdown shown in My Dining.
final class MobileOrderTests: XCTestCase {
    func testMinutesRemainingWhileWindowIsOpen() {
        let now = Date()
        let end = now.addingTimeInterval(22 * 60 + 10)
        XCTAssertEqual(MobileOrderCountdown.minutesRemaining(windowEnd: end, now: now), 22)
    }

    func testNilOncePickupWindowHasPassed() {
        let now = Date()
        XCTAssertNil(MobileOrderCountdown.minutesRemaining(windowEnd: now.addingTimeInterval(-60), now: now))
        XCTAssertNil(MobileOrderCountdown.minutesRemaining(windowEnd: now, now: now))
    }
}
