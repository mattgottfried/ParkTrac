import XCTest
@testable import ParkTrac

/// Planning a future day: saved plans, promotion on the day, date helpers, estimated waits.
final class FutureDayPlanTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func day(_ d: Int, hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    private func plan(_ d: Int, resort: ParkGroup = .disney, rides: [String] = ["a"]) -> DayItinerary {
        DayItinerary(day: day(d), resortRaw: resort.rawValue,
                     rides: rides.map { .init(id: $0, name: $0, parkId: "p") },
                     shows: [], interests: [], notes: "", aiOrder: [], aiSummary: nil, extras: [])
    }

    func testSavingReplacesSameDayAndResortAndSorts() {
        var list = ItineraryStore.saving(plan(12), into: [], calendar: cal)
        list = ItineraryStore.saving(plan(11), into: list, calendar: cal)
        list = ItineraryStore.saving(plan(12, rides: ["b"]), into: list, calendar: cal)
        list = ItineraryStore.saving(plan(12, resort: .universal), into: list, calendar: cal)
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.first?.day, day(11))
        XCTAssertEqual(list.first { $0.resortRaw == ParkGroup.disney.rawValue && $0.day == day(12) }?.rides.map(\.id), ["b"])
    }

    func testPromotesOnTheDayAndDropsPastPlans() {
        let result = ItineraryStore.promote(current: nil, upcoming: [plan(9), plan(10), plan(11)],
                                            now: day(10, hour: 8), calendar: cal)
        XCTAssertEqual(result.current?.day, day(10))
        XCTAssertEqual(result.upcoming.map(\.day), [day(11)], "yesterday's dropped, today's started")
    }

    func testRunningPlanTodayWins() {
        let running = plan(10, rides: ["x"])
        let result = ItineraryStore.promote(current: running, upcoming: [plan(10)], now: day(10, hour: 8), calendar: cal)
        XCTAssertEqual(result.current, running)
        XCTAssertEqual(result.upcoming.count, 1, "kept, not lost")
    }

    func testNothingDueYet() {
        let result = ItineraryStore.promote(current: nil, upcoming: [plan(12)], now: day(10, hour: 8), calendar: cal)
        XCTAssertNil(result.current)
        XCTAssertEqual(result.upcoming.count, 1)
    }

    func testFutureDayHelpers() {
        let now = day(10, hour: 9)
        XCTAssertEqual(FutureDay.title(day(10), now: now, calendar: cal), "Today")
        XCTAssertEqual(FutureDay.title(day(11), now: now, calendar: cal), "Tomorrow")
        let fireworks = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 20, minute: 30))!
        XCTAssertEqual(FutureDay.moving(fireworks, to: day(14), calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 20, minute: 30)))
        XCTAssertEqual(FutureDay.noon(day(14), calendar: cal), day(14, hour: 12))
    }

    func testFutureDayDoesNotPinTheLiveWait() {
        let now = day(10, hour: 10)
        let curve: [Int: Double] = [10: 1, 14: 2]
        let today = RideProfile.waitsByHour(samples: [], currentWait: 30, now: now, parkCurve: curve,
                                            community: [10: 50], calendar: cal)
        XCTAssertEqual(today[10], 30, "today: posted now")
        let future = RideProfile.waitsByHour(samples: [], currentWait: 30, now: now, parkCurve: curve,
                                             community: [10: 50], pinCurrentHour: false, calendar: cal)
        XCTAssertEqual(future[10], 50, "another day: that weekday's typical wait")
        XCTAssertEqual(future[14], 60, "live wait only scales the curve")
    }
}
