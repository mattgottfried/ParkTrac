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
}
