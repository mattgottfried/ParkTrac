import XCTest
@testable import ParkTrac

/// What the app uploads to the alert server (server/logic.ts validates the same fields).
final class InstantAlertsTests: XCTestCase {

    private let now = Date()
    private var today: Date { Calendar.current.startOfDay(for: now) }

    private func ll(endOffset: TimeInterval = 3600) -> LightningLaneWatch {
        LightningLaneWatch(rideId: "slinky", rideName: "Slinky Dog Dash", parkId: "hs", parkName: "Hollywood Studios",
                           day: today, windowStart: now, windowEnd: now.addingTimeInterval(endOffset))
    }

    private func alert(parkId: String? = "hs", resort: ParkGroup? = .universal) -> WaitAlertSnapshot {
        WaitAlertSnapshot(id: "alert-r-1", rideId: "r", rideName: "VelociCoaster", parkId: parkId,
                          parkName: "Islands of Adventure", resort: resort, threshold: 30)
    }

    func testBuildsAllThreeKinds() {
        let reopen = ReopenWatch(rideId: "tron", rideName: "TRON", parkId: "mk", parkName: "Magic Kingdom",
                                 resortRaw: ParkGroup.disney.rawValue, day: today)
        let watches = InstantAlertsPayload.watches(ll: [ll()], alerts: [alert()], reopen: [reopen],
                                                   accessPass: { $0 == .universal ? .aap : nil }, now: now)
        XCTAssertEqual(watches.map(\.kind), [.ll, .wait, .reopen])

        let l = watches[0]
        XCTAssertEqual(l.passLabel, "Lightning Lane")
        XCTAssertEqual(l.bookingAppName, "My Disney Experience")
        XCTAssertEqual(l.expiresAt, l.windowEnd)

        let w = watches[1]
        XCTAssertEqual(w.threshold, 30)
        XCTAssertEqual(w.accessPass, "AAP")
        XCTAssertEqual(w.resort, "Universal Orlando")
        XCTAssertEqual(w.expiresAt, now.addingTimeInterval(24 * 3600).timeIntervalSince1970, accuracy: 1)

        let r = watches[2]
        XCTAssertEqual(r.id, reopen.id.uuidString)
        XCTAssertGreaterThan(r.expiresAt, now.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(r.expiresAt, today.addingTimeInterval(25 * 3600).timeIntervalSince1970)
    }

    func testSkipsWhatTheServerCantWatch() {
        let watches = InstantAlertsPayload.watches(
            ll: [ll(endOffset: -60)],            // window already over
            alerts: [alert(parkId: nil)],        // alert saved before parkId existed
            reopen: [], accessPass: { _ in nil }, now: now)
        XCTAssertTrue(watches.isEmpty)
    }

    func testNoAccessPassWithoutOne() {
        let watches = InstantAlertsPayload.watches(ll: [], alerts: [alert(resort: nil)], reopen: [],
                                                   accessPass: { _ in nil }, now: now)
        XCTAssertNil(watches.first?.accessPass)
        XCTAssertEqual(watches.first?.resort, "Walt Disney World")
    }

    /// Field names are the server's contract — and nil fields must be left out, not sent as null.
    func testJSONMatchesServerContract() throws {
        let watches = InstantAlertsPayload.watches(ll: [ll()], alerts: [alert()], reopen: [],
                                                   accessPass: { _ in nil }, now: now)
        let body = InstantAlertsSyncRequest(deviceId: "d", token: "ab", environment: "production",
                                            timeZone: "America/New_York", watches: watches)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["deviceId", "token", "environment", "timeZone", "watches"])
        let list = try XCTUnwrap(json["watches"] as? [[String: Any]])
        XCTAssertEqual(list[0]["kind"] as? String, "ll")
        XCTAssertNotNil(list[0]["windowStart"] as? Double)
        XCTAssertNil(list[0]["threshold"])
        XCTAssertEqual(list[1]["kind"] as? String, "wait")
        XCTAssertNil(list[1]["accessPass"])
    }

    func testDecodesServerResponse() throws {
        let json = #"{"ok":true,"watching":2,"states":{"a":{"lastNotifiedStart":1800000000},"b":{"fired":true}},"lastError":null,"lastPushAt":1800000000,"serverTime":1}"#
        let r = try JSONDecoder().decode(InstantAlertsSyncResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.watching, 2)
        XCTAssertEqual(r.states?["a"]?.lastNotifiedStart, 1_800_000_000)
        XCTAssertEqual(r.states?["b"]?.fired, true)
        XCTAssertNil(r.lastError)
    }

    func testReopenRule() throws {
        let down = DisplayRide(catalogId: "c", name: "Ride", parkId: "p", location: nil)
        XCTAssertFalse(ReopenWatch.shouldFire(ride: down))
        XCTAssertFalse(ReopenWatch.shouldFire(ride: nil))
        let live = try JSONDecoder().decode(LiveDataEntry.self, from: Data(
            #"{"id":"r","name":"Ride","entityType":"ATTRACTION","status":"OPERATING","queue":{"STANDBY":{"waitTime":20}}}"#.utf8))
        XCTAssertTrue(ReopenWatch.shouldFire(ride: DisplayRide(live: live, parkId: "p", location: nil)))
    }
}
