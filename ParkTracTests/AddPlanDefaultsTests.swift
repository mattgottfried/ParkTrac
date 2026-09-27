import XCTest
@testable import ParkTrac

/// Add to My Day defaults: rounded start times and today's upcoming showtimes.
final class AddPlanDefaultsTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ hour: Int, _ minute: Int, day: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testNextSlot() {
        XCTAssertEqual(AddPlanDefaults.nextSlot(after: at(14, 7), step: 5, calendar: cal), at(14, 10))
        XCTAssertEqual(AddPlanDefaults.nextSlot(after: at(14, 7), step: 30, calendar: cal), at(14, 30))
        XCTAssertEqual(AddPlanDefaults.nextSlot(after: at(14, 30), step: 30, calendar: cal), at(15, 0), "on the mark → next one")
    }

    func testUpcomingShowtimes() {
        let now = at(14, 0)
        let times = [at(20, 0), at(12, 0), at(15, 30), at(10, 0, day: 11)]
        XCTAssertEqual(AddPlanDefaults.upcomingShowtimes(times, now: now, calendar: cal), [at(15, 30), at(20, 0)])
    }
}
