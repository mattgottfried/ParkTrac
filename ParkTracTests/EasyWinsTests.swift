import XCTest
@testable import ParkTrac

/// Easy Wins: shortest absolute waits right now, independent of Good Time to Ride's "usual".
final class EasyWinsTests: XCTestCase {

    private func ride(_ id: String, wait: Int, operating: Bool = true) throws -> DisplayRide {
        let status = operating ? "OPERATING" : "DOWN"
        let live = try JSONDecoder().decode(LiveDataEntry.self, from: Data("""
        {"id":"\(id)","name":"\(id)","entityType":"ATTRACTION","status":"\(status)","queue":{"STANDBY":{"waitTime":\(wait)}}}
        """.utf8))
        return DisplayRide(live: live, parkId: "p", location: nil)
    }

    func testPicksShortWaitsSortedAscending() throws {
        let rides = [try ride("A", wait: 10), try ride("B", wait: 5), try ride("C", wait: 40)]
        let picks = EasyWins.pick(rides: rides)
        XCTAssertEqual(picks.map(\.id), ["B", "A"], "under the 15-min threshold, shortest first")
    }

    func testExcludesGivenIdsAndDownRides() throws {
        let rides = [try ride("A", wait: 10), try ride("B", wait: 8, operating: false)]
        XCTAssertTrue(EasyWins.pick(rides: rides, excluding: ["A"]).isEmpty)
    }

    func testLimit() throws {
        let rides = try (0..<10).map { try ride("r\($0)", wait: 5) }
        XCTAssertEqual(EasyWins.pick(rides: rides, limit: 3).count, 3)
    }
}

/// Nearby & Short: Easy Wins narrowed by actual walking distance.
final class NearbyShortTests: XCTestCase {
    private typealias Candidate = (id: String, waitMinutes: Int?, isOperating: Bool, walkMinutes: Int?)

    func testPicksNearestFirstAmongQualifyingRides() {
        let rides: [Candidate] = [
            ("A", 15, true, 4), ("B", 10, true, 2), ("C", 15, true, 2),
        ]
        // B and C tie on walk distance (2 min); C's shorter wait breaks the tie.
        XCTAssertEqual(NearbyShort.pick(rides: rides), ["C", "B", "A"])
    }

    func testExcludesTooFarOrTooLongAWait() {
        let rides: [Candidate] = [("Far", 5, true, 20), ("Busy", 60, true, 2)]
        XCTAssertTrue(NearbyShort.pick(rides: rides).isEmpty)
    }

    func testExcludesRidesWithNoKnownWalkTime() {
        let rides: [Candidate] = [("Unknown", 5, true, nil)]
        XCTAssertTrue(NearbyShort.pick(rides: rides).isEmpty)
    }

    func testExcludesGivenIdsAndDownRides() {
        let rides: [Candidate] = [("A", 5, true, 2), ("B", 5, false, 2)]
        XCTAssertTrue(NearbyShort.pick(rides: rides, excluding: ["A"]).isEmpty)
    }
}
