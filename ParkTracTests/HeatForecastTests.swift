import XCTest
@testable import ParkTrac

/// Heat heads-up: hot hours, the next window, the heads-up text, and the same-request parse
/// that shares `RainForecastService`'s fetch.
final class HeatForecastTests: XCTestCase {

    func testHotHoursAndNextWindow() {
        let hot = HeatForecast.hotHours([12: 88, 13: 96, 14: 99, 15: 97, 17: 95], threshold: 95)
        XCTAssertEqual(hot, [13, 14, 15, 17])
        XCTAssertEqual(HeatForecast.nextWindow(hotHours: hot, fromHour: 11), HeatForecast.Window(start: 13, end: 16))
        XCTAssertEqual(HeatForecast.nextWindow(hotHours: hot, fromHour: 14), HeatForecast.Window(start: 14, end: 16))
        XCTAssertEqual(HeatForecast.nextWindow(hotHours: hot, fromHour: 16), HeatForecast.Window(start: 17, end: 18))
        XCTAssertNil(HeatForecast.nextWindow(hotHours: hot, fromHour: 18))
    }

    func testHeadline() {
        XCTAssertEqual(HeatForecast.headline(.init(start: 13, end: 16), nowHour: 10), "Heat likely 1–4 PM")
        XCTAssertEqual(HeatForecast.headline(.init(start: 13, end: 16), nowHour: 13), "Heat likely until 4 PM")
    }

    func testParseSharesTheRainRequestShape() throws {
        // The same response `RainForecastService` fetches (precipitation + apparent_temperature)
        let json = #"""
        {"hourly":{"time":["2026-07-10T13:00","2026-07-10T14:00","2026-07-11T14:00"],
                    "precipitation_probability":[10,20,90],
                    "apparent_temperature":[92.0,98.5,110.0]}}
        """#
        let parsed = try XCTUnwrap(HeatForecast.parse(Data(json.utf8), today: "2026-07-10"))
        XCTAssertEqual(parsed, [13: 92.0, 14: 98.5])
        XCTAssertNil(HeatForecast.parse(Data("{}".utf8), today: "2026-07-10"))
    }

    func testHotHoursTreatedLikeWetHoursByThePlanner() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = cal.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 13))!
        let outdoor = PlanRide(id: "out", name: "Outdoor", parkName: "MK", waitByHour: [13: 20, 14: 20], isIndoor: false)
        let indoor = PlanRide(id: "in", name: "Indoor", parkName: "MK", waitByHour: [13: 25, 14: 25], isIndoor: true)
        let hot = DayPlanBuilder.build(rides: [outdoor, indoor], fixed: [], start: start, end: nil,
                                       wetHours: [13], calendar: cal)
        XCTAssertEqual(hot.stops.first?.title, "Indoor", "indoor first in a hot hour, same as a wet one")
    }
}
