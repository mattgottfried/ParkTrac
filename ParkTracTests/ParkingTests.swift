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

    // MARK: Park-close reminder

    private func day(_ type: String, closesIn hours: Double) -> ParkScheduleDay {
        let iso = ISO8601DateFormatter()
        return ParkScheduleDay(date: "2026-10-01", openingTime: nil,
                               closingTime: iso.string(from: now.addingTimeInterval(hours * 3600)),
                               type: type, description: nil)
    }

    func testReminderUsesLatestRegularClose() throws {
        // MK closes in 5 h, EPCOT in 6 h; a party runs later but doesn't count
        let when = try XCTUnwrap(ParkingReminder.fireDate(
            schedule: [day("OPERATING", closesIn: 5), day("OPERATING", closesIn: 6), day("TICKETED_EVENT", closesIn: 8)],
            now: now))
        XCTAssertEqual(when.closing.timeIntervalSince(now), 6 * 3600, accuracy: 1)
        XCTAssertEqual(when.fire.timeIntervalSince(now), 5.5 * 3600, accuracy: 1)
    }

    func testReminderSkippedWhenTooLateOrUnknown() {
        XCTAssertNil(ParkingReminder.fireDate(schedule: [day("OPERATING", closesIn: 0.25)], now: now), "inside the 30 min lead")
        XCTAssertNil(ParkingReminder.fireDate(schedule: [], now: now))
        XCTAssertNil(ParkingReminder.fireDate(schedule: [day("TICKETED_EVENT", closesIn: 5)], now: now))
    }

    // MARK: Quick actions

    /// Info.plist UIApplicationShortcutItemType values must stay valid deep-link hosts.
    func testQuickActionTypesAreDeepLinks() {
        XCTAssertEqual(QuickActions.link(for: "parking"), .parking)
        XCTAssertEqual(QuickActions.link(for: "plan"), .plan)
        XCTAssertEqual(QuickActions.link(for: "waittimes"), .waitTimes)
        XCTAssertNil(QuickActions.link(for: "nope"))
    }

    func testInfoPlistQuickActionsResolve() throws {
        let items = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        XCTAssertFalse(items.isEmpty)
        for item in items {
            let type = try XCTUnwrap(item["UIApplicationShortcutItemType"] as? String)
            XCTAssertNotNil(QuickActions.link(for: type), type)
        }
    }

    // MARK: Lot menus

    func testDisneyStyleDetails() {
        var s = spot(savedAgo: 0, note: "")
        s.details = ParkingDetails(lot: "Magic Kingdom", section: "Zurg", level: nil, row: " 112 ")
        XCTAssertEqual(s.title, "Zurg · Row 112")
        XCTAssertEqual(s.summary, "Magic Kingdom · Zurg · Row 112")
    }

    func testUniversalGarageUsesSignNumber() {
        let d = ParkingDetails(lot: "CityWalk Garages", section: "King Kong", level: nil, row: "410")
        XCTAssertEqual(d.locationText, "King Kong · 410")
    }

    func testGarageLevels() {
        let d = ParkingDetails(lot: "Disney Springs", section: "Lime Garage", level: 3, row: nil)
        XCTAssertEqual(d.locationText, "Lime Garage · Level 3")
    }

    func testNoteStillWorksAndBlanksAreEmpty() {
        XCTAssertTrue(ParkingDetails(lot: " ", section: "", level: nil, row: nil).isEmpty)
        let s = spot(savedAgo: 0, note: "P3 near elevator")
        XCTAssertEqual(s.title, "P3 near elevator")
        XCTAssertEqual(s.summary, "P3 near elevator")
    }

    /// Spots saved before the lot menus existed must still load.
    func testOldSavedSpotDecodes() throws {
        let json = #"{"Walt Disney World":{"latitude":28.4,"longitude":-81.5,"note":"Zurg 112","resortRaw":"Walt Disney World","savedAt":800000000}}"#
        let spots = ParkingService.decode(Data(json.utf8))
        let spot = try XCTUnwrap(spots["Walt Disney World"])
        XCTAssertNil(spot.lot)
        XCTAssertEqual(spot.title, "Zurg 112")
    }

    func testLotCatalog() {
        let mk = ParkingLots.lots(for: .disney).first { $0.name == "Magic Kingdom" }
        XCTAssertEqual(mk?.groups.map(\.name), ["Heroes", "Villains"])
        XCTAssertTrue(mk?.allSections.contains("Zurg") == true)
        XCTAssertEqual(ParkingLots.lots(for: .universal).map(\.name), ["CityWalk Garages", "Epic Universe"])
        XCTAssertTrue(ParkingLots.lots(for: .tokyoDisney).isEmpty, "Japan uses the note")
        // Section names are unique within a lot (they're the picker tags)
        for lot in ParkingLots.lots(for: .disney) + ParkingLots.lots(for: .universal) {
            XCTAssertEqual(Set(lot.allSections).count, lot.allSections.count, lot.name)
        }
    }
}
