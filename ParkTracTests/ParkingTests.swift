import XCTest
import CoreLocation
@testable import ParkTrac

/// Car locator: spot lifetime, storage format, distance text.
final class ParkingTests: XCTestCase {

    private let now = Date()

    private func spot(savedAgo: TimeInterval, note: String = "Zurg 112") -> ParkingSpot {
        ParkingSpot(latitude: 28.4187, longitude: -81.5812, note: note,
                    resortRaw: ParkGroup.disney.rawValue, savedAt: now.addingTimeInterval(-savedAgo))
    }

    func testSpotLastsOneParkDay() {
        XCTAssertTrue(spot(savedAgo: 60).isCurrent(now: now))
        XCTAssertTrue(spot(savedAgo: 15 * 3600).isCurrent(now: now), "late night after an early start")
        XCTAssertFalse(spot(savedAgo: 21 * 3600).isCurrent(now: now), "yesterday's spot")
    }

    func testTitleFallsBack() {
        XCTAssertEqual(spot(savedAgo: 0).title, "Zurg 112")
        XCTAssertEqual(spot(savedAgo: 0, note: "  ").title, "Parking spot")
    }

    func testCoordinateRequiresBoth() {
        var s = spot(savedAgo: 0)
        XCTAssertNotNil(s.coordinate)
        s.longitude = nil
        XCTAssertNil(s.coordinate, "note/photo-only spot")
    }

    /// Stored in iCloud KVS — the format must round-trip, and junk must not crash.
    func testStorageRoundTrip() {
        let spots = [ParkGroup.disney.rawValue: spot(savedAgo: 0),
                     ParkGroup.universal.rawValue: spot(savedAgo: 0, note: "Minions 3")]
        XCTAssertEqual(ParkingService.decode(ParkingService.encode(spots)), spots)
        XCTAssertEqual(ParkingService.decode(Data("nope".utf8)), [:])
        XCTAssertEqual(ParkingService.decode(nil), [:])
    }

    func testWalkTime() {
        XCTAssertEqual(ParkingDistance.walkMinutes(meters: 10), 1)
        // 800 m × 1.2 / 80 m/min = 12 min
        XCTAssertEqual(ParkingDistance.walkMinutes(meters: 800), 12)
        XCTAssertNil(ParkingDistance.walkMinutes(meters: 6000), "too far to walk — show distance only")
    }

    func testDescribeUsesLocaleUnits() {
        let us = ParkingDistance.describe(meters: 800, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(us.contains("mi"), us)
        XCTAssertTrue(us.hasSuffix("about 12 min walk"), us)
        let japan = ParkingDistance.describe(meters: 800, locale: Locale(identifier: "en_JP"))
        XCTAssertTrue(japan.contains("m"), japan)
        XCTAssertFalse(ParkingDistance.describe(meters: 9000).contains("walk"))
    }

    func testDistance() {
        let a = CLLocationCoordinate2D(latitude: 28.4187, longitude: -81.5812)
        let b = CLLocationCoordinate2D(latitude: 28.4187 + 0.0072, longitude: -81.5812)
        XCTAssertEqual(ParkingDistance.meters(from: a, to: b), 800, accuracy: 10)
    }
}
