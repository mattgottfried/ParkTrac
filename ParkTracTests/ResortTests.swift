import XCTest
@testable import ParkTrac

/// Multi-resort support (Orlando + Japan).
final class ResortTests: XCTestCase {

    /// Raw values are persisted in SwiftData and iCloud — changing one orphans saved data.
    func testPersistedRawValuesNeverChange() {
        XCTAssertEqual(ParkGroup.disney.rawValue, "Walt Disney World")
        XCTAssertEqual(ParkGroup.universal.rawValue, "Universal Orlando")
        XCTAssertEqual(ParkGroup.tokyoDisney.rawValue, "Tokyo Disney Resort")
        XCTAssertEqual(ParkGroup.universalJapan.rawValue, "Universal Studios Japan")
    }

    func testBrandAndRegion() {
        XCTAssertEqual(ParkGroup.tokyoDisney.brand, .disney)
        XCTAssertEqual(ParkGroup.universalJapan.brand, .universal)
        XCTAssertTrue(ParkGroup.disney.isOrlando)
        XCTAssertFalse(ParkGroup.tokyoDisney.isOrlando)
        XCTAssertEqual(ParkGroup.orlando, [.disney, .universal])
    }

    func testTimeZoneAndCurrency() {
        XCTAssertEqual(ParkGroup.disney.timeZone.identifier, "America/New_York")
        XCTAssertEqual(ParkGroup.universalJapan.timeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(ParkGroup.universal.currencyCode, "USD")
        XCTAssertEqual(ParkGroup.tokyoDisney.currencyCode, "JPY")
    }

    func testOnlyOrlandoHasHardcodedDestinationIds() {
        XCTAssertNotNil(ParkGroup.disney.destinationId)
        XCTAssertNotNil(ParkGroup.universal.destinationId)
        XCTAssertNil(ParkGroup.tokyoDisney.destinationId)
        XCTAssertNil(ParkGroup.universalJapan.destinationId)
    }

    /// "Today" for schedules must be the park's date, not UTC's or the phone's.
    func testDayStringUsesParkTimeZone() {
        // 16:00 UTC on Sep 26 = 1 AM Sep 27 in Tokyo, noon Sep 26 in Orlando
        let instant = ISO8601DateFormatter().date(from: "2026-09-26T16:00:00Z")!
        XCTAssertEqual(WaitTimesViewModel.dayString(instant, in: ParkGroup.tokyoDisney.timeZone), "2026-09-27")
        XCTAssertEqual(WaitTimesViewModel.dayString(instant, in: ParkGroup.disney.timeZone), "2026-09-26")
    }

    func testReturnPassNames() {
        XCTAssertEqual(ParkGroup.tokyoDisney.returnPassNames.free, "Priority Pass")
        XCTAssertEqual(ParkGroup.tokyoDisney.returnPassNames.paid, "Premier Access")
        XCTAssertEqual(ParkGroup.disney.returnPassNames.short, "LL")
    }

    func testShortTextPrefix() throws {
        let info = LightningLaneInfo(try JSONDecoder().decode(ReturnTimeQueue.self, from: Data(#"{"state":"FINISHED"}"#.utf8)))
        XCTAssertEqual(info?.shortText(prefix: "PP"), "PP sold out")
        XCTAssertEqual(info?.shortText, "LL sold out")
    }

    func testDestinationsDecode() throws {
        let json = """
        {"destinations":[
          {"id":"aaa","name":"Walt Disney World® Resort","slug":"waltdisneyworldresort","parks":[]},
          {"id":"bbb","name":"Tokyo Disney Resort","slug":"tokyodisneyresort","parks":[{"id":"p1","name":"Tokyo Disneyland"}]},
          {"id":"ccc","name":"Universal Studios Japan","slug":"universalstudiosjapan"}
        ]}
        """
        let decoded = try JSONDecoder().decode(DestinationsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.destinations.first { $0.slug == ParkGroup.tokyoDisney.apiSlug }?.id, "bbb")
        XCTAssertEqual(decoded.destinations.first { $0.slug == ParkGroup.universalJapan.apiSlug }?.id, "ccc")
    }

    /// Users created Shortcuts with these exact names — don't change them.
    func testOrlandoShortcutNamesUnchanged() {
        XCTAssertEqual(BookingApp.disney.shortcutName, "Open Disney App")
        XCTAssertEqual(BookingApp.universal.shortcutName, "Open Universal App")
        XCTAssertEqual(BookingApp.for(.tokyoDisney), .tokyoDisney)
    }

    /// Watches saved before passName/resortRaw existed must still load (as Walt Disney World).
    func testOldSavedWatchStillDecodes() throws {
        let old = """
        {"id":"\(UUID().uuidString)","rideId":"r","rideName":"Ride","parkId":"p",
         "day":0,"windowStart":0,"windowEnd":3600}
        """
        let watch = try JSONDecoder().decode(LightningLaneWatch.self, from: Data(old.utf8))
        XCTAssertNil(watch.passName)
        XCTAssertEqual(watch.resort, .disney)
    }
}
