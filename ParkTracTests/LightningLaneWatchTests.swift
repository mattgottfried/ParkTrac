import XCTest
@testable import ParkTrac

/// When a Lightning Lane watch should alert (LightningLaneWatchService.alertStart).
final class LightningLaneWatchTests: XCTestCase {

    private let today = Calendar.current.startOfDay(for: .now)
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
    }

    private func watch(from: Int, to: Int, lastNotified: Date? = nil) -> LightningLaneWatch {
        var w = LightningLaneWatch(rideId: "r", rideName: "Ride", parkId: "p",
                                   day: today, windowStart: at(from), windowEnd: at(to))
        w.lastNotifiedStart = lastNotified
        return w
    }

    /// Builds a LightningLaneInfo through the real decoder
    private func info(state: String = "AVAILABLE", start: Date?) -> LightningLaneInfo? {
        var fields = ["\"state\":\"\(state)\""]
        if let start { fields.append("\"returnStart\":\"\(ISO8601DateFormatter().string(from: start))\"") }
        let json = "{\(fields.joined(separator: ","))}"
        return LightningLaneInfo(try! JSONDecoder().decode(ReturnTimeQueue.self, from: Data(json.utf8)))
    }

    func testAlertsInsideWindow() {
        XCTAssertEqual(LightningLaneWatchService.alertStart(for: watch(from: 12, to: 15), info: info(start: at(13, 35))),
                       at(13, 35))
    }

    func testWindowEdgesAreInclusive() {
        let w = watch(from: 12, to: 15)
        XCTAssertNotNil(LightningLaneWatchService.alertStart(for: w, info: info(start: at(12))))
        XCTAssertNotNil(LightningLaneWatchService.alertStart(for: w, info: info(start: at(15))))
    }

    func testNoAlertOutsideWindow() {
        let w = watch(from: 12, to: 15)
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: info(start: at(11, 59))))
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: info(start: at(15, 1))))
    }

    func testNoAlertWhenNotAvailable() {
        let w = watch(from: 12, to: 15)
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: info(state: "TEMP_FULL", start: at(13))))
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: info(state: "FINISHED", start: nil)))
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: nil))
    }

    func testOnlyEarlierReturnsAlertAgain() {
        let w = watch(from: 12, to: 15, lastNotified: at(14))
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: info(start: at(14))), "same time")
        XCTAssertNil(LightningLaneWatchService.alertStart(for: w, info: info(start: at(14, 30))), "later")
        XCTAssertEqual(LightningLaneWatchService.alertStart(for: w, info: info(start: at(13, 10))), at(13, 10), "earlier")
    }

    func testWindowText() {
        XCTAssertTrue(watch(from: 12, to: 15).windowText.contains("–"))
    }
}
