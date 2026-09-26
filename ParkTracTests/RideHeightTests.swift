import XCTest
@testable import ParkTrac

/// Ride heights (inches in Orlando, cm in Japan), name matching, and USJ area timed entry.
final class RideHeightTests: XCTestCase {

    func testJapanLookupIsPunctuationInsensitive() throws {
        // API names carry ®/™ and different dashes
        let indy = try XCTUnwrap(RideMetadata.info(for: "Indiana Jones® Adventure: Temple of the Crystal Skull", resort: .tokyoDisney))
        XCTAssertEqual(indy.heightCm, 117)
        XCTAssertEqual(RideMetadata.info(for: "Jurassic Park – The Ride", resort: .universalJapan)?.heightCm, 107)
        XCTAssertEqual(RideMetadata.info(for: "Mario Kart: Koopa's Challenge™", resort: .universalJapan)?.heightCm, 102)
    }

    func testContainedNameMatchesVariant() {
        XCTAssertEqual(RideMetadata.info(for: "Hollywood Dream - The Ride ~Backdrop~", resort: .universalJapan)?.heightCm, 132)
    }

    func testResortsDoNotShareTables() {
        // Same name, different ride and unit
        XCTAssertEqual(RideMetadata.info(for: "Space Mountain", resort: .disney)?.heightInches, 44)
        XCTAssertEqual(RideMetadata.info(for: "Space Mountain", resort: .tokyoDisney)?.heightCm, 102)
        XCTAssertNil(RideMetadata.info(for: "Slinky Dog Dash", resort: .tokyoDisney))
        XCTAssertNil(RideMetadata.info(for: "Some New Ride", resort: .universalJapan))
    }

    func testFormattingBothWays() throws {
        let tokyo = try XCTUnwrap(RideMetadata.info(for: "Big Thunder Mountain", resort: .tokyoDisney))
        XCTAssertEqual(HeightFormat.short(tokyo, metric: true), "102 cm")
        XCTAssertEqual(HeightFormat.short(tokyo, metric: false), "40\"")
        let slinky = try XCTUnwrap(RideMetadata.info(for: "Slinky Dog Dash", resort: .disney))
        XCTAssertEqual(HeightFormat.short(slinky, metric: false), "38\"")
        XCTAssertEqual(HeightFormat.short(slinky, metric: true), "97 cm")
        XCTAssertEqual(HeightFormat.spoken(tokyo, metric: true), "102 centimeters")
        let noReq = try XCTUnwrap(RideMetadata.info(for: "Haunted Mansion", resort: .tokyoDisney))
        XCTAssertNil(HeightFormat.short(noReq, metric: true))
    }

    func testGuestHeight() {
        XCTAssertEqual(HeightFormat.guest(cm: 48 * 2.54, metric: false), "4' 0\"")
        XCTAssertEqual(HeightFormat.guest(cm: 121.9, metric: true), "122 cm")
    }

    func testEligibility() throws {
        let flying = try XCTUnwrap(RideMetadata.info(for: "The Flying Dinosaur", resort: .universalJapan))
        XCTAssertFalse(flying.allows(heightCm: 131))
        XCTAssertTrue(flying.allows(heightCm: 132))
        XCTAssertEqual(flying.maxHeightCm, 198)
        // 40" (101.6 cm) child vs a 40" Orlando ride: rides
        let tron = try XCTUnwrap(RideMetadata.info(for: "TRON Lightcycle / Run", resort: .disney))
        XCTAssertTrue(tron.allows(heightCm: 40 * 2.54))
        XCTAssertTrue(RideInfo(heightCm: nil, thrill: .family, type: .family).allows(heightCm: 60))
    }

    func testMetricByResort() {
        XCTAssertTrue(RideMetadata.prefersMetric(.tokyoDisney))
        XCTAssertTrue(RideMetadata.prefersMetric(.universalJapan))
        XCTAssertFalse(RideMetadata.prefersMetric(.universal))
    }

    // MARK: Area timed entry

    func testAreaEntry() {
        XCTAssertTrue(AreaEntry.isOffered(at: .universalJapan))
        XCTAssertFalse(AreaEntry.isOffered(at: .universal))
        XCTAssertEqual(AreaEntry.planId(for: "Super Nintendo World"), "area-supernintendoworld")
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AreaEntry.window(start: start, minutes: 60).end.timeIntervalSince(start), 3600)
        XCTAssertEqual(AreaEntry.window(start: start, minutes: 0).end.timeIntervalSince(start), 15 * 60)
        XCTAssertEqual(AreaEntry.window(start: start, minutes: 999).end.timeIntervalSince(start), 240 * 60)
    }
}
