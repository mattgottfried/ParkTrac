import XCTest
@testable import ParkTrac

/// Ride sheet forecast: the hours shown, "go now" vs "wait until", and the next-hour trend.
final class WaitForecastTests: XCTestCase {

    private let profile = [9: 20, 10: 45, 11: 60, 12: 70, 13: 65, 14: 55, 15: 50, 16: 45,
                           17: 40, 18: 35, 19: 30, 20: 25, 21: 30, 22: 10]

    func testLastHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let ten = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 22))!
        let tenThirty = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 22, minute: 30))!
        XCTAssertEqual(WaitForecast.lastHour(closing: ten, calendar: cal), 21)
        XCTAssertEqual(WaitForecast.lastHour(closing: tenThirty, calendar: cal), 22)
        XCTAssertNil(WaitForecast.lastHour(closing: nil, calendar: cal))
    }

    func testBarsStayInsideParkHours() {
        let bars = WaitForecast.bars(profile: profile, openHour: 10, lastHour: 21)
        XCTAssertEqual(bars.first?.hour, 10)
        XCTAssertEqual(bars.last?.hour, 21)
        XCTAssertFalse(bars.contains { $0.hour == 22 }, "after close")
    }

    func testWaitUntilLaterWhenItSavesTime() {
        XCTAssertEqual(WaitForecast.call(profile: profile, nowHour: 12, currentWait: 70, lastHour: 21),
                       .waitUntil(hour: 20, wait: 25, saves: 45))
    }

    func testGoNowWhenNothingBetterLeft() {
        XCTAssertEqual(WaitForecast.call(profile: profile, nowHour: 19, currentWait: 30, lastHour: 21), .goNow(wait: 30))
        XCTAssertEqual(WaitForecast.call(profile: profile, nowHour: 21, currentWait: 30, lastHour: 21), .goNow(wait: 30))
        XCTAssertNil(WaitForecast.call(profile: profile, nowHour: 12, currentWait: nil, lastHour: 21))
    }

    func testTrend() {
        XCTAssertEqual(WaitForecast.trend(profile: profile, nowHour: 9, currentWait: 20, lastHour: 21),
                       .rising(hour: 10, wait: 45))
        XCTAssertEqual(WaitForecast.trend(profile: profile, nowHour: 13, currentWait: 70, lastHour: 21),
                       .falling(hour: 14, wait: 55))
        XCTAssertNil(WaitForecast.trend(profile: profile, nowHour: 17, currentWait: 40, lastHour: 21))
        XCTAssertNil(WaitForecast.trend(profile: profile, nowHour: 21, currentWait: 30, lastHour: 21), "park closing")
    }
}
