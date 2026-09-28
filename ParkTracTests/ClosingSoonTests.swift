import XCTest
@testable import ParkTrac

/// "Rides closing in about N min" heads-up, from the latest regular (non-ticketed) close.
final class ClosingSoonTests: XCTestCase {
    private func schedule(closing: String, type: String? = "OPERATING") -> ParkScheduleDay {
        ParkScheduleDay(date: "2026-10-10", openingTime: "2026-10-10T09:00:00-04:00",
                        closingTime: closing, type: type, description: nil)
    }

    func testMinutesUntilCloseWithinLead() {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T21:30:00-04:00")!
        let closing = "2026-10-10T22:00:00-04:00"
        XCTAssertEqual(ClosingSoon.minutesUntilClose(schedule: [schedule(closing: closing)], now: now), 30)
    }

    func testNilWhenBeyondTheLeadWindow() {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T19:00:00-04:00")!
        let closing = "2026-10-10T22:00:00-04:00"
        XCTAssertNil(ClosingSoon.minutesUntilClose(schedule: [schedule(closing: closing)], now: now))
    }

    func testNilOncePassed() {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T23:00:00-04:00")!
        let closing = "2026-10-10T22:00:00-04:00"
        XCTAssertNil(ClosingSoon.minutesUntilClose(schedule: [schedule(closing: closing)], now: now))
    }

    func testIgnoresTicketedEventsAndUsesTheLatestRegularClose() {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T21:30:00-04:00")!
        let regular = schedule(closing: "2026-10-10T22:00:00-04:00", type: "OPERATING")
        let party = schedule(closing: "2026-10-11T01:00:00-04:00", type: "TICKETED_EVENT")
        XCTAssertEqual(ClosingSoon.minutesUntilClose(schedule: [regular, party], now: now), 30)
    }
}
