import XCTest
import CoreLocation
@testable import ParkTrac

/// The ride list / hours bar follow the map: zoomed out → all parks, zoomed into a park → that park.
final class MapFocusTests: XCTestCase {
    private let mk = CLLocationCoordinate2D(latitude: 28.4177, longitude: -81.5812)
    private let epcot = CLLocationCoordinate2D(latitude: 28.3747, longitude: -81.5494)
    private var parks: [(id: String, coordinate: CLLocationCoordinate2D)] { [(id: "mk", coordinate: mk), (id: "epcot", coordinate: epcot)] }

    func testZoomedOutIsAllParks() {
        XCTAssertEqual(MapFocus.decide(span: 0.07, center: mk, parks: parks), .allParks)
    }

    func testZoomedIntoAPark() {
        XCTAssertEqual(MapFocus.decide(span: 0.015, center: epcot, parks: parks), .park("epcot"))
        let nearMK = CLLocationCoordinate2D(latitude: mk.latitude + 0.004, longitude: mk.longitude)
        XCTAssertEqual(MapFocus.decide(span: 0.02, center: nearMK, parks: parks), .park("mk"))
    }

    func testInBetweenKeepsCurrent() {
        XCTAssertEqual(MapFocus.decide(span: 0.04, center: mk, parks: parks), .keep)
    }

    func testZoomedIntoSomewhereElseIsAllParks() {
        let springs = CLLocationCoordinate2D(latitude: 28.3702, longitude: -81.5150)  // Disney Springs, ~3.4 km from EPCOT
        XCTAssertEqual(MapFocus.decide(span: 0.015, center: springs, parks: parks), .allParks)
    }
}
