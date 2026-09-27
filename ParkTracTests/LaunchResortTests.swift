import XCTest
import CoreLocation
@testable import ParkTrac

/// Launch screen suggests the resort you're at, else the one you used last.
final class LaunchResortTests: XCTestCase {
    func testSuggestsResortYoureAt() {
        let epcotGate = CLLocationCoordinate2D(latitude: 28.3747, longitude: -81.5494)
        XCTAssertEqual(LaunchResort.suggested(last: .universal, location: epcotGate), .disney)
        let usj = CLLocationCoordinate2D(latitude: 34.6660, longitude: 135.4330)
        XCTAssertEqual(LaunchResort.suggested(last: .disney, location: usj), .universalJapan)
    }

    func testFallsBackToLastUsed() {
        let home = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)  // far from every resort
        XCTAssertEqual(LaunchResort.suggested(last: .tokyoDisney, location: home), .tokyoDisney)
        XCTAssertEqual(LaunchResort.suggested(last: .universal, location: nil), .universal)
    }
}
