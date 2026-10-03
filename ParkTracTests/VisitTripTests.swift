import XCTest
@testable import ParkTrac

/// Trip grouping/comparison ("This Trip So Far" on Visit History) is inferred purely from gaps
/// between logged visit days — no explicit trip boundary exists in RideLog.
final class VisitTripTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func log(_ name: String) -> RideLog {
        RideLog(rideId: name, rideName: name, parkId: "p", parkName: "Park", resort: "Walt Disney World")
    }

    private func visitDay(_ y: Int, _ m: Int, _ d: Int, rides: [String]) -> VisitDay {
        VisitDay(id: day(y, m, d), resort: "Walt Disney World", entries: rides.map(log))
    }

    func testConsecutiveDaysGroupIntoOneTrip() {
        let days = [visitDay(2026, 1, 1, rides: ["A"]), visitDay(2026, 1, 2, rides: ["B", "C"]),
                    visitDay(2026, 1, 3, rides: ["D"])]
        let trips = VisitTripGrouper.group(days, calendar: cal)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].dayCount, 3)
        XCTAssertEqual(trips[0].totalRides, 4)
    }

    func testARestDayStaysInTheSameTrip() {
        // Jan 1, skip Jan 2 (rest day), Jan 3 — still within maxGapDays
        let days = [visitDay(2026, 1, 1, rides: ["A"]), visitDay(2026, 1, 3, rides: ["B"])]
        let trips = VisitTripGrouper.group(days, maxGapDays: 2, calendar: cal)
        XCTAssertEqual(trips.count, 1)
    }

    func testALongGapStartsANewTrip() {
        let days = [visitDay(2026, 1, 1, rides: ["A"]), visitDay(2026, 6, 1, rides: ["B"])]
        let trips = VisitTripGrouper.group(days, calendar: cal)
        XCTAssertEqual(trips.count, 2)
    }

    func testCompareLatestToPreviousByDayCountAndNewRides() throws {
        // Previous trip: 3 days, 1+2+1 = 4 rides total, day-1 has 1 ride
        let previous = [visitDay(2026, 1, 1, rides: ["Space Mountain"]),
                        visitDay(2026, 1, 2, rides: ["Space Mountain", "Pirates"]),
                        visitDay(2026, 1, 3, rides: ["Haunted Mansion"])]
        // Current trip so far: 1 day, 2 rides, one of them new (never ridden on the previous trip)
        let current = [visitDay(2026, 6, 1, rides: ["Space Mountain", "TRON"])]
        let trips = VisitTripGrouper.group(previous + current, calendar: cal)
        XCTAssertEqual(trips.count, 2)
        let comparison = try XCTUnwrap(VisitTripGrouper.compareLatestToPrevious(trips))
        XCTAssertEqual(comparison.currentRides, 2)
        XCTAssertEqual(comparison.priorRidesByThisPoint, 1, "only day 1 of the previous trip, to match current's 1 day so far")
        XCTAssertEqual(comparison.newRideNames, ["TRON"])
        XCTAssertEqual(comparison.rideDifference, 1)
    }

    func testNoComparisonWithFewerThanTwoTrips() {
        let trips = VisitTripGrouper.group([visitDay(2026, 1, 1, rides: ["A"])], calendar: cal)
        XCTAssertNil(VisitTripGrouper.compareLatestToPrevious(trips))
    }

    // MARK: Most-ridden

    func testMostRiddenPicksTheHighestCount() {
        let top = MostRiddenRide.pick(counts: ["Space Mountain": 12, "Pirates": 5, "TRON": 12])
        // Tie broken by name descending, for stable output
        XCTAssertEqual(top?.name, "TRON")
        XCTAssertEqual(top?.count, 12)
    }

    func testNoMostRiddenWithNoLogs() {
        XCTAssertNil(MostRiddenRide.pick(counts: [:]))
    }

    // MARK: Rest reminder

    func testNudgesAfterAStreakOfBackToBackRides() {
        let now = Date()
        let times = [now.addingTimeInterval(-45 * 60), now.addingTimeInterval(-30 * 60),
                     now.addingTimeInterval(-15 * 60), now]
        XCTAssertTrue(RestReminder.shouldNudge(todaysRideTimes: times, now: now))
    }

    func testNoNudgeBelowTheStreakThreshold() {
        let now = Date()
        let times = [now.addingTimeInterval(-10 * 60), now]
        XCTAssertFalse(RestReminder.shouldNudge(todaysRideTimes: times, now: now))
    }

    func testNoNudgeWhenAGapBrokeTheStreak() {
        let now = Date()
        let times = [now.addingTimeInterval(-120 * 60), now.addingTimeInterval(-90 * 60),
                     now.addingTimeInterval(-15 * 60), now]
        XCTAssertFalse(RestReminder.shouldNudge(todaysRideTimes: times, now: now), "a 30-min gap resets the streak")
    }

    func testNoNudgeWhenTheStreakEndedAWhileAgo() {
        let old = Date().addingTimeInterval(-3 * 3600)
        let times = [old.addingTimeInterval(-45 * 60), old.addingTimeInterval(-30 * 60),
                     old.addingTimeInterval(-15 * 60), old]
        XCTAssertFalse(RestReminder.shouldNudge(todaysRideTimes: times), "stale streak, not timely anymore")
    }

    // MARK: Standing time

    func testStandingTimeSumsCompletedRides() {
        let today: [(posted: Int?, actual: Int?)] = [(posted: 40, actual: 35), (posted: 20, actual: nil)]
        XCTAssertEqual(StandingTime.minutes(today: today), 55, "actual wins when timed, else posted")
    }

    func testStandingTimeAddsTheRunningTimer() {
        let now = Date()
        let start = now.addingTimeInterval(-12 * 60)
        XCTAssertEqual(StandingTime.minutes(today: [], activeTimerStart: start, now: now), 12)
    }

    func testStandingTimeZeroWithNothingLogged() {
        XCTAssertEqual(StandingTime.minutes(today: []), 0)
    }

    // MARK: Park Bingo

    func testParkBingoSplitsRiddenFromRemaining() {
        let roster = ["Space Mountain", "Big Thunder", "TRON", "Haunted Mansion"]
        let progress = ParkBingo.progress(roster: roster, riddenThisTrip: ["TRON", "Big Thunder"])
        XCTAssertEqual(progress.ridden, ["Big Thunder", "TRON"])
        XCTAssertEqual(progress.remaining, ["Haunted Mansion", "Space Mountain"])
    }

    func testParkBingoIgnoresRidesNotOnTheRoster() {
        let progress = ParkBingo.progress(roster: ["Space Mountain"], riddenThisTrip: ["Some Other Park's Ride"])
        XCTAssertEqual(progress.ridden, [])
        XCTAssertEqual(progress.remaining, ["Space Mountain"])
    }

    // MARK: Annual streak

    func testAnnualStreakCountsConsecutiveYears() {
        XCTAssertEqual(AnnualStreak.count(years: [2022, 2023, 2024, 2025, 2026], through: 2026), 5)
    }

    func testAnnualStreakStopsAtAGap() {
        XCTAssertEqual(AnnualStreak.count(years: [2020, 2024, 2025, 2026], through: 2026), 3)
    }

    func testAnnualStreakZeroWithNoHistory() {
        XCTAssertEqual(AnnualStreak.count(years: [], through: 2026), 0)
    }

    func testAnnualStreakCountsBackFromLastVisitedYearNotThisYear() {
        // Hasn't visited yet this year (2026), but visited every year through 2025.
        XCTAssertEqual(AnnualStreak.count(years: [2023, 2024, 2025], through: 2026), 3)
    }

    // MARK: Spend pace vs. last trip

    func testSpendComparisonOverTheSameDayCount() {
        // Previous trip: 3 days (Jan 1-3), $40 the first two days ($20/day)
        let previous = [visitDay(2026, 1, 1, rides: ["A"]), visitDay(2026, 1, 2, rides: ["B"]),
                        visitDay(2026, 1, 3, rides: ["C"])]
        // Current trip: 2 days so far (June 1-2), $100 total ($50/day)
        let current = [visitDay(2026, 6, 1, rides: ["D"]), visitDay(2026, 6, 2, rides: ["E"])]
        let trips = VisitTripGrouper.group(previous + current, calendar: cal)
        let purchases: [(amount: Double, date: Date)] = [
            (10, day(2026, 1, 1)), (30, day(2026, 1, 2)), (1000, day(2026, 1, 3)),  // day 3 is past the 2-day cutoff
            (50, day(2026, 6, 1)), (50, day(2026, 6, 2)),
        ]
        let comparison = try! XCTUnwrap(SpendPaceComparer.compare(trips: trips, purchases: purchases, calendar: cal))
        XCTAssertEqual(comparison.previousPerDay, 20)
        XCTAssertEqual(comparison.currentPerDay, 50)
    }

    func testNoSpendComparisonWithFewerThanTwoTrips() {
        let trips = VisitTripGrouper.group([visitDay(2026, 1, 1, rides: ["A"])], calendar: cal)
        XCTAssertNil(SpendPaceComparer.compare(trips: trips, purchases: [], calendar: cal))
    }

    // MARK: Trip highlight day

    func testTripHighlightPicksTheMostRiddenDay() {
        let trip = VisitTripGrouper.group([visitDay(2026, 1, 1, rides: ["A"]),
                                           visitDay(2026, 1, 2, rides: ["B", "C", "D"])], calendar: cal)[0]
        let highlight = try! XCTUnwrap(TripHighlight.bestDay(trip: trip))
        XCTAssertEqual(highlight.date, day(2026, 1, 2))
        XCTAssertEqual(highlight.rideCount, 3)
    }

    func testNoTripHighlightWithNoRides() {
        let trip = VisitTrip(id: day(2026, 1, 1), days: [])
        XCTAssertNil(TripHighlight.bestDay(trip: trip))
    }
}
