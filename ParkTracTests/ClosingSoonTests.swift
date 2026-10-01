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

    func testCustomLeadWindow() {
        let now = ISO8601DateFormatter().date(from: "2026-10-10T21:35:00-04:00")!
        let closing = "2026-10-10T22:00:00-04:00"
        // 25 min out: within a 30-min lead, outside the default 45-min one would still include it,
        // but a tighter 20-min lead should exclude it.
        XCTAssertEqual(ClosingSoon.minutesUntilClose(schedule: [schedule(closing: closing)], now: now, leadMinutes: 30), 25)
        XCTAssertNil(ClosingSoon.minutesUntilClose(schedule: [schedule(closing: closing)], now: now, leadMinutes: 20))
    }
}

/// "One last ride?" wrap-up as the park's about to close.
final class ParkWrapUpTests: XCTestCase {
    private typealias Candidate = (id: String, waitMinutes: Int?, isOperating: Bool)

    func testPicksShortWaitsNotYetRiddenToday() {
        let rides: [Candidate] = [("A", 10, true), ("B", 15, true), ("C", 5, true)]
        XCTAssertEqual(ParkWrapUp.picks(rides: rides, riddenTodayIds: ["C"]), ["A", "B"])
    }

    func testExcludesLongWaitsAndDownRides() {
        let rides: [Candidate] = [("A", 60, true), ("B", 10, false)]
        XCTAssertTrue(ParkWrapUp.picks(rides: rides, riddenTodayIds: []).isEmpty)
    }
}
