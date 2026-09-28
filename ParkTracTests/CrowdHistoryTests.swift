import XCTest
@testable import ParkTrac

/// Crowd calendar from real waits: measured past days, recent-weeks predictions, seasonal fallback.
final class CrowdHistoryTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// Saturday 2026-10-10
    private func day(_ d: Int, month: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: 12))!
    }

    private let data = CrowdDays(slug: "waltdisneyworldresort", parks: [
        .init(id: "mk", name: "Magic Kingdom", days: ["2026-10-03": 50, "2026-09-26": 40, "2026-10-09": 20]),
        .init(id: "ep", name: "EPCOT", days: ["2026-10-03": 30]),
    ])

    func testMeasuredPastDay() {
        XCTAssertEqual(CrowdHistory.source(for: day(3), today: day(10), data: data, calendar: cal), .measured(avg: 40))
        XCTAssertEqual(CrowdHistory.parkLine(on: day(3), data: data, calendar: cal), "Magic Kingdom 50 · EPCOT 30")
    }

    func testPredictsFromRecentSameWeekdays() {
        // Next Saturday: previous Saturdays within 4 weeks before it that are in the past → 10/3 (40) and 9/26 (40)
        XCTAssertEqual(CrowdHistory.source(for: day(17), today: day(10), data: data, calendar: cal),
                       .recent(avg: 40, days: 2))
    }

    func testSeasonalWhenTooLittleDataOrTooFarAhead() {
        XCTAssertEqual(CrowdHistory.source(for: day(16), today: day(10), data: data, calendar: cal), .seasonal,
                       "only one earlier Friday")
        XCTAssertEqual(CrowdHistory.source(for: day(5, month: 12), today: day(10), data: data, calendar: cal), .seasonal)
        XCTAssertEqual(CrowdHistory.source(for: day(17), today: day(10), data: nil, calendar: cal), .seasonal)
    }

    func testLevelUsesAverageWait() {
        XCTAssertEqual(CrowdHistory.level(for: day(9), resort: .disney, data: data, today: day(10), calendar: cal), .moderate,
                       "20 min average → Moderate")
    }

    // MARK: Best park today (multi-resort trips)

    func testBestParkPicksTheLeastCrowded() {
        let best = BestParkToday.pick(resorts: [.disney, .universal]) { resort in
            resort == .disney ? .high : .low
        }
        XCTAssertEqual(best?.resort, .universal)
        XCTAssertEqual(best?.level, .low)
    }

    func testNoBestParkWithOnlyOneResort() {
        XCTAssertNil(BestParkToday.pick(resorts: [.disney]) { _ in .low })
    }

    func testNoBestParkWithoutAnyData() {
        XCTAssertNil(BestParkToday.pick(resorts: [.disney, .universal]) { _ in nil })
    }
}
