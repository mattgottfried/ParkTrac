import XCTest
@testable import ParkTrac

/// "Good time to ride": usual wait from recorded history, and when a wait counts as a deal.
final class GoodTimeToRideTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// 2 PM today
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 14, minute: 0))!
    }

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testUsualFromEarlierDaysAtThisTime() throws {
        // 3 samples on each of 2 earlier days around 2 PM
        let samples: [(date: Date, wait: Int)] = [
            (date: at(daysAgo: 1, hour: 13, minute: 30), wait: 60), (date: at(daysAgo: 1, hour: 14), wait: 70), (date: at(daysAgo: 1, hour: 15), wait: 80),
            (date: at(daysAgo: 3, hour: 13), wait: 65), (date: at(daysAgo: 3, hour: 14), wait: 75), (date: at(daysAgo: 3, hour: 15), wait: 70),
            (date: at(daysAgo: 2, hour: 9), wait: 5),   // morning — different time of day, ignored
        ]
        let usual = try XCTUnwrap(GoodTimeToRide.usual(samples: samples, now: now, calendar: calendar))
        XCTAssertEqual(usual.basis, .usualAtThisTime)
        XCTAssertEqual(usual.minutes, 70)
    }

    func testOneDayOfHistoryIsNotEnough() {
        let samples = (0..<8).map { (date: at(daysAgo: 1, hour: 14, minute: $0 * 5), wait: 70) }
        XCTAssertNil(GoodTimeToRide.usual(samples: samples, now: now, calendar: calendar))
    }

    func testFallsBackToEarlierToday() throws {
        // Six samples this morning; the last half hour is ignored so the current dip doesn't count
        var samples: [(date: Date, wait: Int)] = (0..<6).map { (date: at(daysAgo: 0, hour: 11, minute: $0 * 10), wait: 60) }
        samples.append((date: at(daysAgo: 0, hour: 13, minute: 50), wait: 10))
        let usual = try XCTUnwrap(GoodTimeToRide.usual(samples: samples, now: now, calendar: calendar))
        XCTAssertEqual(usual.basis, .earlierToday)
        XCTAssertEqual(usual.minutes, 60)
    }

    func testDealRules() {
        let usual = GoodTimeToRide.Usual(minutes: 70, basis: .usualAtThisTime)
        XCTAssertEqual(GoodTimeToRide.deal(rideId: "r", wait: 35, isOperating: true, usual: usual)?.savedMinutes, 35)
        XCTAssertNil(GoodTimeToRide.deal(rideId: "r", wait: 50, isOperating: true, usual: usual), "only 29% below")
        XCTAssertNil(GoodTimeToRide.deal(rideId: "r", wait: 35, isOperating: false, usual: usual), "not running")
        XCTAssertNil(GoodTimeToRide.deal(rideId: "r", wait: nil, isOperating: true, usual: usual))
        XCTAssertNil(GoodTimeToRide.deal(rideId: "r", wait: 35, isOperating: true, usual: nil))
        // Short usual waits aren't worth a nudge
        XCTAssertNil(GoodTimeToRide.deal(rideId: "r", wait: 5, isOperating: true,
                                         usual: .init(minutes: 15, basis: .usualAtThisTime)))
        // Needs at least 15 minutes saved
        XCTAssertNil(GoodTimeToRide.deal(rideId: "r", wait: 12, isOperating: true,
                                         usual: .init(minutes: 25, basis: .usualAtThisTime)))
    }

    func testText() {
        let usual = GoodTimeToRide.Deal(rideId: "r", wait: 35, usual: .init(minutes: 70, basis: .usualAtThisTime))
        XCTAssertEqual(usual.shortText, "usually ~70")
        XCTAssertEqual(usual.longText, "usually ~70 min at this time")
        let today = GoodTimeToRide.Deal(rideId: "r", wait: 20, usual: .init(minutes: 60, basis: .earlierToday))
        XCTAssertEqual(today.shortText, "was ~60 earlier")
    }

    func testMedian() {
        XCTAssertNil(GoodTimeToRide.median([]))
        XCTAssertEqual(GoodTimeToRide.median([5]), 5)
        XCTAssertEqual(GoodTimeToRide.median([10, 30, 20]), 20)
        XCTAssertEqual(GoodTimeToRide.median([10, 20, 30, 40]), 25)
    }
}
