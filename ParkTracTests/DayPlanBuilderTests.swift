import XCTest
@testable import ParkTrac

/// Smart Planner engine, request constraints and Siri's "what should I ride next".
final class DayPlanBuilderTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute))!
    }

    private func ride(_ id: String, _ waits: [Int: Int]) -> PlanRide {
        PlanRide(id: id, name: id, parkName: "MK", waitByHour: waits, rideMinutes: 10)
    }

    // MARK: Profile

    func testProfilePrefersHistoryThenScalesLiveWait() {
        let samples: [(date: Date, wait: Int)] = [(at(15), 80), (at(15, 20), 90), (at(15, 40), 70)]
        let curve: [Int: Double] = [10: 20, 12: 40, 15: 60]
        let profile = RideProfile.waitsByHour(samples: samples, currentWait: 30, now: at(10), parkCurve: curve, calendar: cal)
        XCTAssertEqual(profile[10], 30, "current hour is the live wait")
        XCTAssertEqual(profile[12], 60, "30 × 40/20")
        XCTAssertEqual(profile[15], 80, "3 recorded samples → median beats the curve")
    }

    func testWaitLookupFallsBackToNearestHour() {
        let r = ride("a", [9: 10, 14: 50])
        XCTAssertEqual(r.wait(at: at(13), calendar: cal), 50)
        XCTAssertEqual(r.wait(at: at(8), calendar: cal), 10)
        XCTAssertEqual(ride("b", [:]).wait(at: at(8), calendar: cal), 30)
    }

    // MARK: Builder

    func testRidesGoWhenTheyreShortest() {
        // Early ride is short now and long later; late ride is the opposite
        let early = ride("early", [9: 10, 10: 60, 11: 60, 12: 60])
        let late = ride("late", [9: 70, 10: 70, 11: 5, 12: 5])
        let plan = DayPlanBuilder.build(rides: [late, early], fixed: [], start: at(9), end: at(13), calendar: cal)
        XCTAssertEqual(plan.stops.map(\.title), ["early", "late"])
        XCTAssertTrue(plan.unscheduled.isEmpty)
    }

    func testFixedEventsStayPutAndRidesFitAround() throws {
        let long = ride("long", [9: 90, 10: 90, 11: 90])
        let short = ride("short", [9: 10, 10: 10, 11: 10])
        let dinner = FixedEvent(title: "Lunch", kind: "dining", start: at(10), minutes: 60)
        let plan = DayPlanBuilder.build(rides: [long, short], fixed: [dinner], start: at(9), end: at(12, 30), calendar: cal)
        let titles = plan.stops.map(\.title)
        XCTAssertEqual(titles.first, "short", "only the short ride fits before lunch")
        let lunch = try XCTUnwrap(plan.stops.first { $0.title == "Lunch" })
        XCTAssertEqual(lunch.start, at(10))
        // After lunch (11:00), the 90-min ride + walk + 10 min ride ends ~12:48 > 12:30 → doesn't fit
        XCTAssertEqual(plan.unscheduled, ["long"])
    }

    func testNoOverlaps() {
        let rides = (0..<6).map { ride("r\($0)", [9: 20, 10: 25, 11: 30, 12: 20]) }
        let show = FixedEvent(title: "Parade", kind: "show", start: at(11), minutes: 25)
        let plan = DayPlanBuilder.build(rides: rides, fixed: [show], start: at(9), end: nil, calendar: cal)
        for (a, b) in zip(plan.stops, plan.stops.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start.addingTimeInterval(1), "\(a.title) overlaps \(b.title)")
        }
        XCTAssertEqual(plan.stops.count, 7)
    }

    // MARK: Constraints

    func testNameMatching() {
        XCTAssertTrue(PlanConstraints.matches("seven dwarfs", "Seven Dwarfs Mine Train"))
        XCTAssertTrue(PlanConstraints.matches("Space Mountain", "Space Mountain"))
        XCTAssertFalse(PlanConstraints.matches("it", "Haunted Mansion"), "too short to match")
    }

    func testTimeParsing() {
        XCTAssertEqual(PlanConstraints.date("18:30", on: at(9), calendar: cal), at(18, 30))
        XCTAssertNil(PlanConstraints.date("25:00", on: at(9), calendar: cal))
        XCTAssertNil(PlanConstraints.date("", on: at(9), calendar: cal))
    }

    func testSelectRidesHonorsAvoid() {
        let splash = RideInfo(heightInches: 40, thrill: .moderate, type: .water, lightningLane: false)
        let coaster = RideInfo(heightInches: 38, thrill: .moderate, type: .coaster, lightningLane: true)
        let rides: [(id: String, name: String, info: RideInfo?)] = [
            ("tiana", "Tiana's Bayou Adventure", splash),
            ("7dmt", "Seven Dwarfs Mine Train", coaster),
            ("hm", "Haunted Mansion", nil),
        ]
        var c = PlanConstraints()
        c.mustRide = ["Seven Dwarfs", "Tiana's Bayou Adventure"]
        c.avoidKinds = ["water"]
        XCTAssertEqual(c.selectRides(from: rides, fallback: []), ["7dmt"])
        // Nothing named → keep the fallback (Must-Dos), still minus avoided
        let none = PlanConstraints(avoid: ["Haunted Mansion"])
        XCTAssertEqual(none.selectRides(from: rides, fallback: ["hm", "tiana"]), ["tiana"])
    }

    func testPlainTextFallback() {
        let c = PlanConstraints.fromPlainText("we want Space Mountain and the parade",
                                              rideNames: ["Space Mountain", "Jungle Cruise"],
                                              showNames: ["Festival of Fantasy Parade"])
        XCTAssertEqual(c.mustRide, ["Space Mountain"])
        XCTAssertTrue(c.includeShows.isEmpty, "\"the parade\" isn't the show's name")
    }

    // MARK: Siri "what should I ride next"

    func testNextRidePriority() {
        let picks = NextRideAdvisor.pick([
            .init(name: "Jungle Cruise", parkName: "MK", wait: 10, usual: nil, isMustDo: false),
            .init(name: "Space Mountain", parkName: "MK", wait: 25, usual: nil, isMustDo: true),
            .init(name: "Peter Pan", parkName: "MK", wait: 30, usual: 70, isMustDo: false),
            .init(name: "Seven Dwarfs", parkName: "MK", wait: 40, usual: 90, isMustDo: true),
        ])
        XCTAssertEqual(picks.map(\.name), ["Seven Dwarfs", "Peter Pan"])
        XCTAssertEqual(NextRideAdvisor.dialog(picks),
                       "Go for Seven Dwarfs at MK — 40 minutes now, usually about 90. Also good: Peter Pan, 30 minutes.")
        XCTAssertTrue(NextRideAdvisor.dialog([]).contains("Nothing is posting"))
    }
}
