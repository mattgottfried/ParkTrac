import XCTest
@testable import ParkTrac

/// The character meet checklist seeds from `allCharacterAppearances`, keyed by character + park
/// like `BucketListService` keys restaurants — a duplicate key would silently seed nothing for
/// the second entry, so guard against that in the data itself.
final class CharacterMeetTests: XCTestCase {

    func testNoDuplicateSeedKeys() {
        let keys = allCharacterAppearances.map { "\($0.character)|\($0.park)" }
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate character+park in allCharacterAppearances")
    }

    func testEveryAppearanceHasAResortAndPark() {
        for appearance in allCharacterAppearances {
            XCTAssertFalse(appearance.character.isEmpty)
            XCTAssertFalse(appearance.park.isEmpty)
            XCTAssertNotNil(ParkGroup(rawValue: appearance.resort), "\(appearance.resort) must match a ParkGroup raw value")
        }
    }

    func testNewMeetDefaultsToNotMet() {
        let meet = CharacterMeet(character: "Test", park: "Test Park", resort: ParkGroup.disney.rawValue)
        XCTAssertFalse(meet.isMet)
        XCTAssertNil(meet.metDate)
        XCTAssertTrue(meet.photoData.isEmpty)
    }
}
