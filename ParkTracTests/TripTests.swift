import XCTest
@testable import ParkTrac

/// Trip Planner: countdown, stored format, yen ↔ dollar.
final class TripTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func day(_ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }

    func testCountdown() {
        let start = day(11, 5), end = day(11, 12)
        XCTAssertEqual(TripCountdown.status(start: start, end: end, now: day(10, 1), calendar: cal), .upcoming(days: 35))
        XCTAssertEqual(TripCountdown.status(start: start, end: end, now: day(11, 4, hour: 23), calendar: cal), .upcoming(days: 1))
        XCTAssertEqual(TripCountdown.status(start: start, end: end, now: day(11, 5, hour: 6), calendar: cal), .during(day: 1, of: 8))
        XCTAssertEqual(TripCountdown.status(start: start, end: end, now: day(11, 12, hour: 22), calendar: cal), .during(day: 8, of: 8))
        XCTAssertEqual(TripCountdown.status(start: start, end: end, now: day(11, 13), calendar: cal), .over)
    }

    func testCountdownText() {
        XCTAssertEqual(TripCountdown.upcoming(days: 42).text(tripName: "Japan"), "Japan in 42 days")
        XCTAssertEqual(TripCountdown.upcoming(days: 1).text(tripName: "Japan"), "Japan is tomorrow!")
        XCTAssertEqual(TripCountdown.during(day: 3, of: 8).text(tripName: "Japan"), "Japan · Day 3 of 8")
        XCTAssertNil(TripCountdown.over.text(tripName: "Japan"))
    }

    func testJapanTripDefaults() {
        let trip = Trip.japan(start: day(11, 5), end: day(11, 12))
        XCTAssertTrue(trip.isJapan)
        XCTAssertEqual(trip.resorts, [.tokyoDisney, .universalJapan])
        XCTAssertEqual(trip.checklist.count, Trip.japanChecklist.count)
        XCTAssertFalse(trip.checklist.contains(where: \.isDone))
    }

    /// Stored in iCloud KVS — must round-trip.
    func testStorageRoundTrip() throws {
        var trip = Trip.japan(start: day(11, 5), end: day(11, 12))
        trip.checklist[0].isDone = true
        XCTAssertEqual(TripService.decode(TripService.encode(trip)), trip)
        XCTAssertNil(TripService.decode(Data("junk".utf8)))
        XCTAssertNil(TripService.decode(nil))
    }

    func testRateParsing() {
        XCTAssertEqual(CurrencyConverter.parseRate(Data(#"{"amount":1.0,"base":"USD","date":"2026-09-26","rates":{"JPY":149.52}}"#.utf8)), 149.52)
        XCTAssertNil(CurrencyConverter.parseRate(Data(#"{"rates":{"EUR":0.9}}"#.utf8)))
        XCTAssertNil(CurrencyConverter.parseRate(Data("nope".utf8)))
    }

    func testDollarsText() {
        XCTAssertEqual(CurrencyConverter.dollarsText(yen: 1500, yenPerDollar: 150), "≈ $10.00")
        XCTAssertEqual(CurrencyConverter.dollarsText(yen: 30000, yenPerDollar: 150), "≈ $200")
    }

    // MARK: Budget pacing

    func testPaceSpreadsRemainingBudgetOverRemainingDays() throws {
        // Trip runs day(11,5)...day(11,12) — today is day 3 of 8, so 6 days including today are left
        let pacing = try XCTUnwrap(BudgetPacer.pace(budget: 600, spent: 150, today: day(11, 7), tripEnd: day(11, 12), calendar: cal))
        XCTAssertEqual(pacing.remainingDays, 6)
        XCTAssertEqual(pacing.remainingBudget, 450)
        XCTAssertEqual(pacing.perDay, 75)
    }

    func testPaceOnTheLastDay() throws {
        let pacing = try XCTUnwrap(BudgetPacer.pace(budget: 600, spent: 500, today: day(11, 12), tripEnd: day(11, 12), calendar: cal))
        XCTAssertEqual(pacing.remainingDays, 1)
        XCTAssertEqual(pacing.perDay, 100)
    }

    func testPaceGoesNegativeWhenOverspent() throws {
        let pacing = try XCTUnwrap(BudgetPacer.pace(budget: 600, spent: 700, today: day(11, 10), tripEnd: day(11, 12), calendar: cal))
        XCTAssertEqual(pacing.remainingBudget, -100)
        XCTAssertLessThan(pacing.perDay, 0)
    }

    func testNoPacingAfterTripEndsOrWithNoBudget() {
        XCTAssertNil(BudgetPacer.pace(budget: 600, spent: 100, today: day(11, 13), tripEnd: day(11, 12), calendar: cal))
        XCTAssertNil(BudgetPacer.pace(budget: 0, spent: 100, today: day(11, 7), tripEnd: day(11, 12), calendar: cal))
    }

    // MARK: Vacation Calendar

    func testVacationCalendarDaysInclusive() {
        let days = VacationCalendar.days(start: day(11, 5), end: day(11, 8), calendar: cal)
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(days.first, cal.startOfDay(for: day(11, 5)))
        XCTAssertEqual(days.last, cal.startOfDay(for: day(11, 8)))
    }

    func testVacationCalendarSingleDayTrip() {
        XCTAssertEqual(VacationCalendar.days(start: day(11, 5), end: day(11, 5), calendar: cal).count, 1)
    }

    // MARK: Year-to-date spend

    func testYearToDateSpendSumsOnlyThatYear() {
        let purchases = [(amount: 50.0, date: day(1, 5)), (amount: 30.0, date: day(11, 5)),
                         (amount: 100.0, date: cal.date(from: DateComponents(year: 2025, month: 6, day: 1))!)]
        XCTAssertEqual(YearToDateSpend.total(purchases: purchases, year: 2026, calendar: cal), 80)
    }

    func testYearToDateSpendZeroWithNoPurchases() {
        XCTAssertEqual(YearToDateSpend.total(purchases: [], year: 2026, calendar: cal), 0)
    }
}
