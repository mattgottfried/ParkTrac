import XCTest
@testable import ParkTrac

/// Real vs posted wait from Rode It! stopwatch logs.
final class WaitRealityTests: XCTestCase {

    private func t(_ id: String, _ posted: Int, _ actual: Int) -> WaitReality.Timed {
        WaitReality.Timed(rideId: id, posted: posted, actual: actual)
    }

    func testThisRideFirst() throws {
        let timed = [t("a", 60, 45), t("a", 40, 30), t("b", 30, 30), t("b", 30, 30), t("b", 30, 30)]
        let adj = try XCTUnwrap(WaitReality.adjustment(for: "a", timed: timed))
        XCTAssertEqual(adj.basis, .thisRide(2))
        XCTAssertEqual(adj.actual(posted: 60), 45)
        XCTAssertTrue(adj.isWorthShowing(posted: 60))
        XCTAssertEqual(adj.sourceText, "from 2 of your rides on it")
    }

    func testFallsBackToAllRides() throws {
        let timed = [t("a", 60, 30), t("b", 40, 20), t("c", 20, 10), t("d", 50, 25), t("e", 30, 15)]
        let adj = try XCTUnwrap(WaitReality.adjustment(for: "z", timed: timed))
        XCTAssertEqual(adj.basis, .allRides(5))
        XCTAssertEqual(adj.actual(posted: 60), 30)
    }

    func testTooLittleData() {
        XCTAssertNil(WaitReality.adjustment(for: "a", timed: [t("a", 60, 45), t("b", 30, 20)]))
        XCTAssertNil(WaitReality.adjustment(for: "a", timed: [t("a", 0, 10), t("a", 0, 10)]), "posted 0 is ignored")
    }

    func testSmallDifferenceIsNotShown() throws {
        let adj = try XCTUnwrap(WaitReality.adjustment(for: "a", timed: [t("a", 30, 28), t("a", 30, 29)]))
        XCTAssertFalse(adj.isWorthShowing(posted: 30))
    }
}
