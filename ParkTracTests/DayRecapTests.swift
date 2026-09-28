import XCTest
@testable import ParkTrac

/// Day recap numbers from Rode It! logs and purchases.
final class DayRecapTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ hour: Int, day: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private let wdw = ParkGroup.disney.rawValue

    private var logs: [DayRecapBuilder.LogRow] {
        [
            .init(name: "TRON", posted: 60, actual: 40, at: at(10), resort: wdw),
            .init(name: "Space Mountain", posted: 30, actual: 35, at: at(11), resort: wdw),
            .init(name: "TRON", posted: 45, actual: nil, at: at(20), resort: wdw),
            .init(name: "Peter Pan", posted: nil, actual: nil, at: at(12), resort: wdw),
            .init(name: "Yesterday", posted: 10, actual: 10, at: at(12, day: 9), resort: wdw),
            .init(name: "Other resort", posted: 10, actual: 10, at: at(12), resort: ParkGroup.universal.rawValue),
        ]
    }

    func testRecapNumbers() throws {
        let purchases = [DayRecapBuilder.Purchase(amount: 12.5, date: at(13), resort: wdw),
                         DayRecapBuilder.Purchase(amount: 99, date: at(13, day: 9), resort: wdw)]
        let recap = DayRecapBuilder.make(date: at(9), resort: .disney, logs: logs, purchases: purchases, calendar: cal)
        XCTAssertEqual(recap.rideCount, 4)
        XCTAssertEqual(recap.uniqueRides, 3)
        XCTAssertEqual(recap.rides.map(\.name), ["TRON", "Space Mountain", "Peter Pan", "TRON"], "in time order")
        XCTAssertEqual(recap.minutesInLine, 40 + 35 + 45)
        XCTAssertEqual(recap.beatPostedBy, 20 - 5)
        let best = try XCTUnwrap(recap.bestRide)
        XCTAssertEqual(best.name, "TRON")
        XCTAssertEqual(best.text, "Waited 40 min, posted 60")
        XCTAssertEqual(recap.mostRidden?.name, "TRON")
        XCTAssertEqual(recap.mostRidden?.count, 2)
        XCTAssertEqual(recap.spent, 12.5)
        XCTAssertEqual(recap.costPerRide, 12.5 / 4)
    }

    func testNoCostPerRideWithoutSpendOrRides() {
        let recap = DayRecapBuilder.make(date: at(9), resort: .disney, logs: [], purchases: [], calendar: cal)
        XCTAssertNil(recap.costPerRide)
    }

    func testBestRideFallsBackToShortestPosted() {
        let recap = DayRecapBuilder.make(
            date: at(9), resort: .disney,
            logs: [.init(name: "A", posted: 50, actual: nil, at: at(10), resort: wdw),
                   .init(name: "B", posted: 15, actual: nil, at: at(11), resort: wdw)],
            purchases: [], calendar: cal)
        XCTAssertEqual(recap.bestRide?.name, "B")
        XCTAssertNil(recap.beatPostedBy)
        XCTAssertNil(recap.mostRidden)
    }

    func testRecapDays() {
        XCTAssertEqual(DayRecapBuilder.days(logs: logs, resort: .disney, calendar: cal),
                       [cal.startOfDay(for: at(10)), cal.startOfDay(for: at(10, day: 9))])
    }

    // MARK: Year in Review

    private func on(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testYearRecapAggregatesTheWholeYear() {
        let yearLogs: [DayRecapBuilder.LogRow] = [
            .init(name: "Space Mountain", posted: 40, actual: nil, at: on(2026, 1, 1), resort: wdw),
            .init(name: "Space Mountain", posted: 40, actual: nil, at: on(2026, 1, 1), resort: wdw),
            .init(name: "TRON", posted: 50, actual: nil, at: on(2026, 6, 15), resort: wdw),  // gap → new trip
            .init(name: "Old", posted: 10, actual: nil, at: on(2025, 12, 31), resort: wdw),  // last year, excluded
        ]
        let purchases = [DayRecapBuilder.Purchase(amount: 25, date: on(2026, 1, 1), resort: wdw),
                         DayRecapBuilder.Purchase(amount: 100, date: on(2025, 12, 31), resort: wdw)]
        let recap = YearRecapBuilder.make(year: 2026, resort: .disney, logs: yearLogs, purchases: purchases, calendar: cal)
        XCTAssertEqual(recap.rideCount, 3)
        XCTAssertEqual(recap.uniqueRides, 2)
        XCTAssertEqual(recap.daysVisited, 2)
        XCTAssertEqual(recap.tripCount, 2)
        XCTAssertEqual(recap.topRide?.name, "Space Mountain")
        XCTAssertEqual(recap.topRide?.count, 2)
        XCTAssertEqual(recap.spent, 25)
    }

    func testYearRecapEmptyYear() {
        let recap = YearRecapBuilder.make(year: 2026, resort: .disney, logs: [], purchases: [], calendar: cal)
        XCTAssertEqual(recap.rideCount, 0)
        XCTAssertNil(recap.topRide)
    }

    func testYearsWithHistoryNewestFirst() {
        let yearLogs: [DayRecapBuilder.LogRow] = [
            .init(name: "A", posted: nil, actual: nil, at: on(2024, 3, 1), resort: wdw),
            .init(name: "B", posted: nil, actual: nil, at: on(2026, 3, 1), resort: wdw),
        ]
        XCTAssertEqual(YearRecapBuilder.years(logs: yearLogs, resort: .disney, calendar: cal), [2026, 2024])
    }
}
