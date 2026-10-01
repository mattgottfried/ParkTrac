import XCTest
@testable import ParkTrac

/// "Missed it, catch the next one" hint on a show's row.
final class ShowEncoreTests: XCTestCase {
    func testLaterShowtimeWhenNextIsTooSoon() {
        let now = Date()
        let next = now.addingTimeInterval(10 * 60)       // 10 min — too soon
        let later = now.addingTimeInterval(90 * 60)
        let result = ShowEncore.later(showtimes: [next, later], next: next, now: now)
        XCTAssertEqual(result, later)
    }

    func testNilWhenNextIsFarEnoughOff() {
        let now = Date()
        let next = now.addingTimeInterval(30 * 60)       // 30 min — reachable
        let later = now.addingTimeInterval(90 * 60)
        XCTAssertNil(ShowEncore.later(showtimes: [next, later], next: next, now: now))
    }

    func testNilWithNoNextShowtime() {
        XCTAssertNil(ShowEncore.later(showtimes: [], next: nil))
    }

    func testNilWhenThereIsNoShowingAfterTheNextOne() {
        let now = Date()
        let next = now.addingTimeInterval(5 * 60)
        XCTAssertNil(ShowEncore.later(showtimes: [next], next: next, now: now))
    }
}
