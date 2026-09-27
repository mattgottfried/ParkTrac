import XCTest
@testable import ParkTrac

/// Must-Do down / back-up alerts: the rule (mirrors server/logic.ts downTransition) and the sync payload.
final class MustDoDownTests: XCTestCase {

    func testTransitions() {
        XCTAssertEqual(MustDoDown.transition(isDown: false, status: "DOWN").event, .down)
        XCTAssertNil(MustDoDown.transition(isDown: true, status: "DOWN").event, "still down → quiet")
        XCTAssertEqual(MustDoDown.transition(isDown: true, status: "OPERATING").event, .backUp)
        XCTAssertNil(MustDoDown.transition(isDown: false, status: "OPERATING").event)
        let closed = MustDoDown.transition(isDown: true, status: "CLOSED")
        XCTAssertNil(closed.event, "closing for the night resets quietly")
        XCTAssertFalse(closed.isDown)
    }

    func testPayloadIncludesMustDos() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rides = [
            MustDoRide(rideId: "r1", rideName: "TRON", parkId: "mk", parkName: "Magic Kingdom", resortRaw: ParkGroup.disney.rawValue),
            MustDoRide(rideId: "r2", rideName: "No park yet", parkId: "", parkName: "", resortRaw: ParkGroup.disney.rawValue),
        ]
        let watches = InstantAlertsPayload.watches(ll: [], alerts: [], reopen: [], mustDo: rides,
                                                   accessPass: { _ in nil }, now: now)
        XCTAssertEqual(watches.count, 1, "rides without a park id can't be watched remotely")
        let w = try XCTUnwrap(watches.first)
        XCTAssertEqual(w.kind, .down)
        XCTAssertEqual(w.id, "mustdo-r1")
        XCTAssertEqual(w.parkId, "mk")
        XCTAssertGreaterThan(w.expiresAt, now.timeIntervalSince1970)
        let json = String(decoding: try JSONEncoder().encode(w), as: UTF8.self)
        XCTAssertTrue(json.contains(#""kind":"down""#), json)
    }
}
