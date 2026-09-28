import XCTest
@testable import ParkTrac

/// Guards against SeedData drifting out of sync with `BucketListService.closedRestaurantKeys`:
/// a permanently-closed restaurant should never be re-seeded to a new install, and its
/// successor (if any) should be.
final class SeedDataTests: XCTestCase {

    func testClosedRestaurantsAreNotSeeded() {
        let seededKeys = Set(allSeedRestaurants.map { "\($0.name)|\($0.park)" })
        for closedKey in BucketListService.closedRestaurantKeys {
            XCTAssertFalse(seededKeys.contains(closedKey), "\(closedKey) closed permanently — should be removed from allSeedRestaurants")
        }
    }

    func testSuccessorRestaurantIsSeeded() {
        XCTAssertTrue(allSeedRestaurants.contains { $0.name == "Fat One's Hot Dogs & Italian Ice" && $0.park == "CityWalk" },
                     "replaces Hot Dog Hall of Fame® in the same spot")
    }

    func testNoDuplicateSeedRestaurantKeys() {
        let keys = allSeedRestaurants.map { "\($0.name)|\($0.park)" }
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate name+park in allSeedRestaurants")
    }
}
