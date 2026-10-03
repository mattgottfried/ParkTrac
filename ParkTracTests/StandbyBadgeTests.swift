import XCTest
@testable import ParkTrac

/// Standby-avoidance badges, built only from RideLog's own fields.
final class StandbyBadgeTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ hour: Int, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute))!
    }

    func testEarlyBirdNeedsBothEarlyAndShort() {
        XCTAssertTrue(StandbyBadgeRules.isEarlyBird(rides: [(riddenAt: at(8), waitMinutes: 10)], calendar: cal))
        XCTAssertFalse(StandbyBadgeRules.isEarlyBird(rides: [(riddenAt: at(8), waitMinutes: 40)], calendar: cal),
                       "early but not short")
        XCTAssertFalse(StandbyBadgeRules.isEarlyBird(rides: [(riddenAt: at(10), waitMinutes: 10)], calendar: cal),
                       "short but not early")
    }

    func testNightOwlAtOrAfterNinePM() {
        XCTAssertTrue(StandbyBadgeRules.isNightOwl(rides: [at(21)], calendar: cal))
        XCTAssertFalse(StandbyBadgeRules.isNightOwl(rides: [at(20, minute: 59)], calendar: cal))
    }

    func testShortWaitStreakNeedsTenQualifyingRides() {
        XCTAssertTrue(StandbyBadgeRules.hasShortWaitStreak(waitMinutes: Array(repeating: 10, count: 10)))
        XCTAssertFalse(StandbyBadgeRules.hasShortWaitStreak(waitMinutes: Array(repeating: 10, count: 9)))
        XCTAssertFalse(StandbyBadgeRules.hasShortWaitStreak(waitMinutes: Array(repeating: 20, count: 10)))
    }

    func testBeatTheWaitMargin() {
        XCTAssertTrue(StandbyBadgeRules.hasBeatTheWait(rides: [(posted: 60, actual: 35)]))
        XCTAssertFalse(StandbyBadgeRules.hasBeatTheWait(rides: [(posted: 60, actual: 45)]))
        XCTAssertFalse(StandbyBadgeRules.hasBeatTheWait(rides: [(posted: nil, actual: 35)]))
    }

    func testMarathonDayNeedsFifteenInOneDay() {
        let day1 = Array(repeating: at(10), count: 15)
        XCTAssertTrue(StandbyBadgeRules.hasMarathonDay(rides: day1, calendar: cal))
        let split = Array(repeating: at(10), count: 8) + Array(repeating: cal.date(byAdding: .day, value: 1, to: at(10))!, count: 8)
        XCTAssertFalse(StandbyBadgeRules.hasMarathonDay(rides: split, calendar: cal), "split across two days, neither alone reaches 15")
    }
}
