import XCTest
@testable import ParkTrac

/// Rain plan: wet hours, the next window, the heads-up text, indoor rides, and the planner.
final class RainPlanTests: XCTestCase {

    func testWetHoursAndNextWindow() {
        let wet = RainForecast.wetHours([13: 20, 15: 60, 16: 80, 17: 50, 19: 70])
        XCTAssertEqual(wet, [15, 16, 17, 19])
        XCTAssertEqual(RainForecast.nextWindow(wetHours: wet, fromHour: 12), RainForecast.Window(start: 15, end: 18))
        XCTAssertEqual(RainForecast.nextWindow(wetHours: wet, fromHour: 16), RainForecast.Window(start: 16, end: 18))
        XCTAssertEqual(RainForecast.nextWindow(wetHours: wet, fromHour: 18), RainForecast.Window(start: 19, end: 20))
        XCTAssertNil(RainForecast.nextWindow(wetHours: wet, fromHour: 20))
    }

    func testHeadline() {
        XCTAssertEqual(RainForecast.headline(.init(start: 15, end: 17), nowHour: 12), "Rain likely 3–5 PM")
        XCTAssertEqual(RainForecast.headline(.init(start: 11, end: 13), nowHour: 9), "Rain likely 11 AM–1 PM")
        XCTAssertEqual(RainForecast.headline(.init(start: 14, end: 16), nowHour: 14), "Rain likely until 4 PM")
    }

    func testParseOpenMeteo() throws {
        let json = #"{"hourly":{"time":["2026-10-10T14:00","2026-10-10T15:00","2026-10-11T15:00"],"precipitation_probability":[10,65,90]}}"#
        let parsed = try XCTUnwrap(RainForecast.parse(Data(json.utf8), today: "2026-10-10"))
        XCTAssertEqual(parsed, [14: 10, 15: 65])
        XCTAssertNil(RainForecast.parse(Data("{}".utf8), today: "2026-10-10"))
    }

    func testIndoorRides() {
        XCTAssertTrue(RideMetadata.isIndoor(name: "Haunted Mansion", resort: .disney), "dark ride")
        XCTAssertTrue(RideMetadata.isIndoor(name: "Space Mountain", resort: .disney), "indoor coaster")
        XCTAssertTrue(RideMetadata.isIndoor(name: "Space Mountain", resort: .tokyoDisney))
        XCTAssertTrue(RideMetadata.isIndoor(name: "Rock 'n' Roller Coaster Starring Aerosmith", resort: .disney))
        XCTAssertFalse(RideMetadata.isIndoor(name: "Slinky Dog Dash", resort: .disney))
        XCTAssertFalse(RideMetadata.isIndoor(name: "Some Unknown Ride", resort: .disney))
    }

    func testPlannerPutsIndoorRidesInTheRain() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15))!
        let outdoor = PlanRide(id: "out", name: "Outdoor", parkName: "MK", waitByHour: [15: 20, 16: 20], isIndoor: false)
        let indoor = PlanRide(id: "in", name: "Indoor", parkName: "MK", waitByHour: [15: 25, 16: 25], isIndoor: true)
        let dry = DayPlanBuilder.build(rides: [outdoor, indoor], fixed: [], start: start, end: nil, calendar: cal)
        XCTAssertEqual(dry.stops.first?.title, "Outdoor", "shorter wait first when it's dry")
        let wet = DayPlanBuilder.build(rides: [outdoor, indoor], fixed: [], start: start, end: nil,
                                       wetHours: [15], calendar: cal)
        XCTAssertEqual(wet.stops.first?.title, "Indoor", "indoor first while it rains")
    }

    func testPromptMentionsRain() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let at9 = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9))!
        let input = PlannerAI.PlanInput(
            rides: [.init(name: "Haunted Mansion", waitsByHour: [9: 20], isMustDo: false, isIndoor: true)],
            shows: [], dining: [], start: at9, end: nil, notes: "", rainHours: [16, 15])
        let text = PlannerAI.prompt(input, calendar: cal)
        XCTAssertTrue(text.contains("- Haunted Mansion (indoor): expected wait"), text)
        XCTAssertTrue(text.contains("Rain likely: 3pm, 4pm — put indoor rides then"), text)
    }
}
