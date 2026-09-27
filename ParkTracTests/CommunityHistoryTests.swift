import XCTest
@testable import ParkTrac

/// Community wait history from the server feeding each ride's expected waits.
final class CommunityHistoryTests: XCTestCase {

    func testDecodeAndHours() throws {
        let json = #"{"parkId":"mk","weekday":6,"days":9,"rides":{"r1":{"9":20,"14":65,"bad":5,"30":1}},"builtAt":1}"#
        let summary = try XCTUnwrap(CommunityHistoryService.decode(Data(json.utf8)))
        XCTAssertEqual(summary.days, 9)
        XCTAssertEqual(summary.waitsByHour(rideId: "r1"), [9: 20, 14: 65])
        XCTAssertEqual(summary.waitsByHour(rideId: "nope"), [:])
        XCTAssertNil(CommunityHistoryService.decode(Data("x".utf8)))
    }

    func testDayKeyUsesTheResortTimeZone() {
        // 2027-01-15 15:00 UTC = Friday 10am in Orlando, Saturday midnight in Tokyo
        let instant = Date(timeIntervalSince1970: 1_800_025_200)
        let ny = CommunityHistoryService.dayKey(instant, timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(ny.day, "2027-01-15")
        XCTAssertEqual(ny.weekday, 6)
        let tokyo = CommunityHistoryService.dayKey(instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(tokyo.day, "2027-01-16")
        XCTAssertEqual(tokyo.weekday, 7)
    }

    func testProfilePrefersOwnHistoryThenCommunityThenCurve() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ day: Int, _ hour: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 15))!
        }
        // Own history at 9am (3 samples)
        let samples = [(date: at(3, 9), wait: 15), (date: at(4, 9), wait: 15), (date: at(5, 9), wait: 15)]
        let curve: [Int: Double] = [9: 1, 10: 1, 11: 2, 12: 2]
        let profile = RideProfile.waitsByHour(samples: samples, currentWait: 30, now: at(10, 10),
                                              parkCurve: curve, community: [9: 50, 11: 70], calendar: cal)
        XCTAssertEqual(profile[9], 15, "own history wins")
        XCTAssertEqual(profile[10], 30, "current hour is live")
        XCTAssertEqual(profile[11], 70, "community next")
        XCTAssertEqual(profile[12], 60, "then live × park curve")
    }
}
