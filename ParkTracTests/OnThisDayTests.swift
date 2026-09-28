import XCTest
@testable import ParkTrac

final class OnThisDayTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func log(_ name: String, on date: Date) -> RideLog {
        RideLog(rideId: name, rideName: name, parkId: "p", parkName: "Magic Kingdom", resort: "Walt Disney World", riddenAt: date)
    }

    func testFindsOneYearAgo() {
        let logs = [
            log("Space Mountain", on: date(2025, 9, 28)),
            log("Space Mountain", on: date(2025, 9, 28)),
            log("Pirates", on: date(2025, 9, 28)),
        ]
        let memory = OnThisDayMemories.find(logs: logs, resort: "Walt Disney World", today: date(2026, 9, 28), calendar: cal)
        XCTAssertEqual(memory?.yearsAgo, 1)
        XCTAssertEqual(memory?.rideCount, 3)
        XCTAssertEqual(memory?.repeatRide?.name, "Space Mountain")
        XCTAssertEqual(memory?.repeatRide?.count, 2)
    }

    func testFallsBackToAnOlderYear() {
        let logs = [log("TRON", on: date(2023, 9, 28))]
        let memory = OnThisDayMemories.find(logs: logs, resort: "Walt Disney World", today: date(2026, 9, 28), calendar: cal)
        XCTAssertEqual(memory?.yearsAgo, 3)
    }

    func testIgnoresOtherDatesAndResorts() {
        let logs = [
            log("TRON", on: date(2025, 9, 27)),                                   // wrong day
            RideLog(rideId: "x", rideName: "x", parkId: "p", parkName: "IOA", resort: "Universal Orlando", riddenAt: date(2025, 9, 28)),
        ]
        XCTAssertNil(OnThisDayMemories.find(logs: logs, resort: "Walt Disney World", today: date(2026, 9, 28), calendar: cal))
    }

    func testNoMemoryWithNoHistory() {
        XCTAssertNil(OnThisDayMemories.find(logs: [], resort: "Walt Disney World", today: date(2026, 9, 28), calendar: cal))
    }
}
