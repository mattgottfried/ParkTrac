import XCTest
import CoreLocation
@testable import ParkTrac

/// Deep links, CSV export, day summary, walking estimate.
final class DeepLinkTests: XCTestCase {

    private func link(_ s: String) -> DeepLink? { DeepLink(url: URL(string: s)!) }

    func testParsesEveryRoute() {
        XCTAssertEqual(link("thrilltrack://waittimes"), .waitTimes)
        XCTAssertEqual(link("thrilltrack://ride/abc-123"), .ride(id: "abc-123"))
        XCTAssertEqual(link("thrilltrack://timer"), .activeTimer)
        XCTAssertEqual(link("thrilltrack://plan"), .plan)
        XCTAssertEqual(link("thrilltrack://dining"), .dining)
        XCTAssertEqual(link("thrilltrack://settings"), .settings)
        XCTAssertEqual(link("thrilltrack://bucketlist"), .bucketList)
        XCTAssertEqual(link("thrilltrack://parking"), .parking)
        XCTAssertEqual(link("thrilltrack://planner"), .planner)
    }

    func testRejectsUnknownOrForeign() {
        XCTAssertNil(link("thrilltrack://nowhere"))
        XCTAssertNil(link("https://example.com/plan"))
    }

    func testRideWithoutIdFallsBackToWaitTimes() {
        XCTAssertEqual(link("thrilltrack://ride"), .waitTimes)
    }

    func testRoundTrip() {
        let links: [DeepLink] = [.waitTimes, .ride(id: "slinky-dog"), .activeTimer, .plan, .dining, .settings, .bucketList, .parking, .planner]
        for l in links { XCTAssertEqual(DeepLink(url: l.url), l, "\(l)") }
    }

    func testRideIdWithSpacesRoundTrips() {
        let l = DeepLink.ride(id: "ride with spaces")
        XCTAssertEqual(DeepLink(url: l.url), l)
    }
}

final class ExportTests: XCTestCase {

    func testCSVEscaping() {
        XCTAssertEqual(CSV.escape("plain"), "plain")
        XCTAssertEqual(CSV.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSV.escape("two\nlines"), "\"two\nlines\"")
    }

    func testCSVMake() {
        let csv = CSV.make(header: ["Ride", "Wait"], rows: [["Soarin', Around the World", "45"]])
        XCTAssertEqual(csv, "Ride,Wait\n\"Soarin', Around the World\",45\n")
    }

    func testDaySummaryWithRides() {
        let text = DaySummary.text(
            date: .now, resort: "Walt Disney World",
            rides: [.init(name: "Space Mountain", postedWait: 45, actualWait: 38),
                    .init(name: "Haunted Mansion", postedWait: nil, actualWait: nil)],
            planDone: 3, planTotal: 5, spent: 42.5)
        XCTAssertTrue(text.contains("Rides (2):"))
        XCTAssertTrue(text.contains("• Space Mountain — posted 45 min, waited 38"))
        XCTAssertTrue(text.contains("• Haunted Mansion"))
        XCTAssertTrue(text.contains("Beat the posted waits by 7 min total."))
        XCTAssertTrue(text.contains("Plan: 3 of 5 done"))
        XCTAssertTrue(text.contains("Spent:"))
    }

    func testDaySummaryListsPeople() {
        let text = DaySummary.text(date: .now, resort: "Walt Disney World", rides: [],
                                   planDone: 0, planTotal: 0, spent: 0,
                                   people: ["Matt", "Heather", "Jake"])
        XCTAssertTrue(text.contains("With Matt, Heather & Jake"))
    }

    func testDaySummaryEmpty() {
        let text = DaySummary.text(date: .now, resort: "Universal Orlando Resort", rides: [],
                                   planDone: 0, planTotal: 0, spent: 0)
        XCTAssertTrue(text.contains("No rides logged yet."))
        XCTAssertFalse(text.contains("Plan:"))
        XCTAssertFalse(text.contains("Spent:"))
    }
}

final class WalkEstimateTests: XCTestCase {

    private let castle = CLLocationCoordinate2D(latitude: 28.4194, longitude: -81.5812)

    func testSameSpotIsOneMinute() {
        XCTAssertEqual(WalkEstimate.minutes(from: castle, to: castle), 1)
    }

    func testRoughlyScalesWithDistance() throws {
        // ~0.0072° latitude ≈ 800 m → 800 × 1.35 / 80 ≈ 13.5 min
        let there = CLLocationCoordinate2D(latitude: castle.latitude + 0.0072, longitude: castle.longitude)
        let minutes = try XCTUnwrap(WalkEstimate.minutes(from: castle, to: there))
        XCTAssertTrue((12...15).contains(minutes), "\(minutes)")
    }

    func testTooFarReturnsNil() {
        let epcot = CLLocationCoordinate2D(latitude: 28.3747, longitude: -81.5494)  // ~6 km away
        XCTAssertNil(WalkEstimate.minutes(from: castle, to: epcot))
    }
}

final class NameListTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(NameList.format([]), "")
        XCTAssertEqual(NameList.format(["Matt"]), "Matt")
        XCTAssertEqual(NameList.format(["Matt", "Heather"]), "Matt & Heather")
        XCTAssertEqual(NameList.format(["Matt", "Heather", "Jake"]), "Matt, Heather & Jake")
        XCTAssertEqual(NameList.format(["A", "B", "C", "D", "E"]), "A, B, C & 2 more")
    }

    func testIgnoresBlanks() {
        XCTAssertEqual(NameList.format(["  Matt ", "", "Heather"]), "Matt & Heather")
    }
}
