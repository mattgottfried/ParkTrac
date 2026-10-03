import XCTest
@testable import ParkTrac

/// The once-a-day consolidated morning notification (weather/crowd/top Must-Do pick).
final class MorningBriefingTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testFiresOnlyWithinTheMorningWindowOnATripDay() {
        let range = day(2026, 6, 1)...day(2026, 6, 5)
        XCTAssertTrue(MorningBriefing.shouldFire(hour: 7, resort: "Walt Disney World", tripResorts: ["Walt Disney World"],
                                                 tripRange: range, today: day(2026, 6, 2)))
        XCTAssertFalse(MorningBriefing.shouldFire(hour: 14, resort: "Walt Disney World", tripResorts: ["Walt Disney World"],
                                                  tripRange: range, today: day(2026, 6, 2)), "outside the morning window")
    }

    func testNoFireOutsideTheTripDateRange() {
        let range = day(2026, 6, 1)...day(2026, 6, 5)
        XCTAssertFalse(MorningBriefing.shouldFire(hour: 7, resort: "Walt Disney World", tripResorts: ["Walt Disney World"],
                                                  tripRange: range, today: day(2026, 7, 1)))
    }

    func testNoFireWhenTripDoesntCoverThisResort() {
        let range = day(2026, 6, 1)...day(2026, 6, 5)
        XCTAssertFalse(MorningBriefing.shouldFire(hour: 7, resort: "Universal Orlando", tripResorts: ["Walt Disney World"],
                                                  tripRange: range, today: day(2026, 6, 2)))
    }

    func testNoFireWithoutAPlannedTrip() {
        XCTAssertFalse(MorningBriefing.shouldFire(hour: 7, resort: "Walt Disney World", tripResorts: [],
                                                  tripRange: nil, today: day(2026, 6, 2)))
    }

    func testBodyJoinsWhicheverPartsAreAvailable() {
        XCTAssertEqual(MorningBriefing.body(weather: "Rain likely today", crowd: "High crowds expected", mustDo: nil),
                      "Rain likely today · High crowds expected")
        XCTAssertEqual(MorningBriefing.body(weather: nil, crowd: nil, mustDo: nil), "Have a great day at the parks!")
    }
}
