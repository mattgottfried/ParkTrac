import XCTest
@testable import ParkTrac

/// Genie-style planning: Apple Intelligence order, live plan state, interests, Tip Board.
final class GenieTests: XCTestCase {

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

    // MARK: Ordered build (Apple Intelligence's order)

    func testOrderedBuildKeepsOrderAndFixedEvents() throws {
        let a = ride("A", [9: 20, 10: 20, 11: 20, 12: 20])
        let b = ride("B", [9: 20, 10: 20, 11: 20, 12: 20])
        let lunch = FixedEvent(title: "Lunch", kind: "dining", start: at(9, 40), minutes: 60)
        // B first (as the model asked); A doesn't fit before lunch → after it
        let plan = DayPlanBuilder.build(ordered: [b, a], fixed: [lunch], start: at(9), end: at(13), calendar: cal)
        XCTAssertEqual(plan.stops.map(\.title), ["B", "Lunch", "A"])
        XCTAssertEqual(try XCTUnwrap(plan.stops.last).start, at(10, 40))
    }

    func testOrderedBuildStopsAtClose() {
        let a = ride("A", [9: 50])
        let b = ride("B", [9: 50, 10: 50])
        let plan = DayPlanBuilder.build(ordered: [a, b], fixed: [], start: at(9), end: at(10), calendar: cal)
        XCTAssertEqual(plan.stops.map(\.title), ["A"])
        XCTAssertEqual(plan.unscheduled, ["B"])
    }

    func testResolveOrderMatchesLooselyAndKeepsEveryPick() {
        let rides = [ride("Space Mountain", [:]), ride("Seven Dwarfs Mine Train", [:]), ride("Jungle Cruise", [:])]
        let order = PlannerAI.resolveOrder(["seven dwarfs", "Space Mountain", "Space Mountain", "Made Up Ride"], rides: rides)
        XCTAssertEqual(order.map(\.name), ["Seven Dwarfs Mine Train", "Space Mountain", "Jungle Cruise"])
    }

    func testPromptListsPicksWaitsAndSetTimes() {
        let input = PlannerAI.PlanInput(
            rides: [.init(name: "Slinky Dog Dash", waitsByHour: [9: 45, 10: 70], isMustDo: true)],
            shows: [.init(title: "Fantasmic!", time: at(20, 30))],
            dining: [.init(title: "Sci-Fi Dine-In", time: at(18))],
            start: at(9), end: at(21), notes: "Rise right before close",
            interests: ["Coasters"])
        let text = PlannerAI.prompt(input, calendar: cal)
        XCTAssertTrue(text.contains("- Slinky Dog Dash (Must-Do): expected wait in minutes — 9am 45, 10am 70"), text)
        XCTAssertTrue(text.contains("- Show: Fantasmic! at 20:30"))
        XCTAssertTrue(text.contains("- Dining: Sci-Fi Dine-In at 18:00"))
        XCTAssertTrue(text.contains("park closes at 21:00"))
        XCTAssertTrue(text.contains("Interests: Coasters"))
        XCTAssertTrue(text.contains("Guest's notes: Rise right before close"))
    }

    func testGroundedExtrasDropsInventedAndRepeatedDining() {
        let invented = PlanConstraints.Event(title: "Dinner at Be Our Guest", time: "21:00", minutes: 60)
        let again = PlanConstraints.Event(title: "Dinner at Be Our Guest", time: "22:00", minutes: 60)
        // No notes → nothing the model adds survives
        XCTAssertEqual(PlannerAI.groundedExtras([invented, again], notes: ""), [])
        // Notes that don't mention a meal → dropped
        XCTAssertEqual(PlannerAI.groundedExtras([invented], notes: "Ride TRON right before close"), [])
        // Asked for dinner → kept once
        XCTAssertEqual(PlannerAI.groundedExtras([invented, again], notes: "dinner at 9"), [invented])
        let snack = PlanConstraints.Event(title: "Snack break", time: "15:00", minutes: 20)
        let snack2 = PlanConstraints.Event(title: "Afternoon snack", time: "15:10", minutes: 20)
        XCTAssertEqual(PlannerAI.groundedExtras([snack, snack2], notes: "snack around 3"), [snack])
    }

    func testEventKind() {
        XCTAssertEqual(PlanConstraints.eventKind(for: "Dinner at Be Our Guest"), "dining")
        XCTAssertEqual(PlanConstraints.eventKind(for: "Snack break"), "break")
    }

    // MARK: Live plan state

    private func itinerary() -> DayItinerary {
        DayItinerary(day: cal.startOfDay(for: at(9)), resortRaw: ParkGroup.disney.rawValue,
                     rides: [.init(id: "a", name: "A", parkId: "p"), .init(id: "b", name: "B", parkId: "p"),
                             .init(id: "c", name: "C", parkId: "p")],
                     shows: [], interests: [.coasters], notes: "", aiOrder: ["c", "a", "b"], aiSummary: nil, extras: [])
    }

    func testRemainingFollowsAIOrderAndDropsDoneAndSkipped() {
        var it = itinerary()
        XCTAssertEqual(it.remainingRides.map(\.id), ["c", "a", "b"])
        it.doneIds = ["c"]
        it.skippedIds = ["b"]
        XCTAssertEqual(it.remainingRides.map(\.id), ["a"])
    }

    func testItineraryRoundTrips() throws {
        var it = itinerary()
        it.extras = [.init(title: "Dinner", kind: "dining", start: at(18), minutes: 75)]
        let data = try JSONEncoder().encode(it)
        XCTAssertEqual(ItineraryService.decode(data), it)
        XCTAssertNil(ItineraryService.decode(Data("x".utf8)))
    }

    // MARK: Interests

    func testInterestMatching() {
        let coaster = RideInfo(heightInches: 40, thrill: .thrilling, type: .coaster, lightningLane: true)
        let boat = RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false)
        XCTAssertTrue(Interest.coasters.matches(coaster))
        XCTAssertTrue(Interest.thrill.matches(coaster))
        XCTAssertTrue(Interest.gentle.matches(boat))
        XCTAssertTrue(Interest.darkRides.matches(boat))
        XCTAssertFalse(Interest.water.matches(boat))
        XCTAssertEqual(Interest.from(["Roller coasters", "slow rides", "coaster"]), [.coasters, .gentle])
    }

    func testInterestSuggestions() {
        let coaster = RideInfo(heightInches: 40, thrill: .thrilling, type: .coaster, lightningLane: true)
        let spinner = RideInfo(heightInches: nil, thrill: .family, type: .spinner, lightningLane: false)
        let picks = InterestSuggestions.pick([
            .init(id: "1", name: "Far coaster", wait: 10, walk: 15, info: coaster),
            .init(id: "2", name: "Near coaster", wait: 15, walk: 2, info: coaster),
            .init(id: "3", name: "Long coaster", wait: 60, walk: 1, info: coaster),
            .init(id: "4", name: "Teacups", wait: 5, walk: 1, info: spinner),
            .init(id: "5", name: "Planned coaster", wait: 5, walk: 1, info: coaster),
        ], interests: [.coasters], excluding: ["5"])
        XCTAssertEqual(picks.map(\.name), ["Near coaster", "Far coaster"])
        XCTAssertTrue(InterestSuggestions.pick([.init(id: "1", name: "x", wait: 1, walk: 1, info: coaster)],
                                               interests: [], excluding: []).isEmpty)
    }

    // MARK: Tip Board

    func testBestTimeToday() throws {
        let best = try XCTUnwrap(TipBoard.best(profile: [10: 60, 14: 25, 20: 25, 21: 40], fromHour: 12, untilHour: 21))
        XCTAssertEqual(best.hour, 14)
        XCTAssertEqual(best.wait, 25)
        XCTAssertNil(TipBoard.best(profile: [10: 5], fromHour: 12, untilHour: 21))
    }

    func testGoodNow() {
        let low = TipBoard.Row(id: "r", name: "R", waitNow: 30, isOperating: true, usualNow: 70,
                               bestHour: 20, bestWait: 20, isMustDo: true)
        XCTAssertTrue(low.isGoodNow, "well below usual")
        let atBest = TipBoard.Row(id: "r", name: "R", waitNow: 24, isOperating: true, usualNow: nil,
                                  bestHour: 20, bestWait: 20, isMustDo: false)
        XCTAssertTrue(atBest.isGoodNow, "within 5 of today's low")
        let busy = TipBoard.Row(id: "r", name: "R", waitNow: 60, isOperating: true, usualNow: 65,
                                bestHour: 20, bestWait: 20, isMustDo: false)
        XCTAssertFalse(busy.isGoodNow)
        let closed = TipBoard.Row(id: "r", name: "R", waitNow: nil, isOperating: false, usualNow: 70,
                                  bestHour: nil, bestWait: nil, isMustDo: false)
        XCTAssertFalse(closed.isGoodNow)
    }

    // MARK: Lightning Lane value

    private func llInfo(_ json: String) throws -> LightningLaneInfo {
        try XCTUnwrap(LightningLaneInfo(JSONDecoder().decode(ReturnTimeQueue.self, from: Data(json.utf8))))
    }

    func testLightningLaneValueCountsMinutesAndPaidCost() throws {
        let multi = try llInfo(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:00:00Z"}"#)
        let single = try llInfo(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:00:00Z","price":{"amount":1500,"currency":"USD","formatted":"$15.00"}}"#)
        let summary = LightningLaneValue.summary(rides: [
            (name: "Free Return", standbyWait: 65, multiPass: multi, singlePass: nil),
            (name: "Paid Return", standbyWait: 50, multiPass: nil, singlePass: single),
            (name: "No LL", standbyWait: 40, multiPass: nil, singlePass: nil),
            (name: "Too short to matter", standbyWait: 3, multiPass: multi, singlePass: nil),
        ])
        XCTAssertEqual(summary.rides.count, 2, "only rides with an available LL return and a wait worth counting")
        XCTAssertEqual(summary.totalMinutesSaved, (65 - 5) + (50 - 5))
        XCTAssertEqual(summary.totalCost, 15.0)
        XCTAssertTrue(summary.hasPaidRides)
    }

    func testLightningLaneValueEmptyWhenNothingAvailable() {
        let summary = LightningLaneValue.summary(rides: [(name: "Closed", standbyWait: nil, multiPass: nil, singlePass: nil)])
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.totalMinutesSaved, 0)
        XCTAssertFalse(summary.hasPaidRides)
    }

    func testBestPickIsTheMostMinutesSaved() throws {
        let multi = try llInfo(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:00:00Z"}"#)
        let summary = LightningLaneValue.summary(rides: [
            (name: "Free Return", standbyWait: 65, multiPass: multi, singlePass: nil),
            (name: "Shorter Return", standbyWait: 40, multiPass: multi, singlePass: nil),
        ])
        let best = try XCTUnwrap(LightningLaneValue.bestPick(summary))
        XCTAssertEqual(best.name, "Free Return")
    }

    func testBestPickPrefersFreeOverPaidOnATie() throws {
        let multi = try llInfo(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:00:00Z"}"#)
        let single = try llInfo(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:00:00Z","price":{"amount":1500,"currency":"USD","formatted":"$15.00"}}"#)
        let summary = LightningLaneValue.summary(rides: [
            (name: "Paid Return", standbyWait: 50, multiPass: nil, singlePass: single),
            (name: "Free Return", standbyWait: 50, multiPass: multi, singlePass: nil),
        ])
        let best = try XCTUnwrap(LightningLaneValue.bestPick(summary))
        XCTAssertEqual(best.name, "Free Return")
    }

    func testNoBestPickWhenNothingAvailable() {
        XCTAssertNil(LightningLaneValue.bestPick(LightningLaneValue.Summary(rides: [])))
    }
}
