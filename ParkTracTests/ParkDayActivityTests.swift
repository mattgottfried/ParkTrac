import XCTest
@testable import ParkTrac

/// Park Day Live Activity content from the live plan.
final class ParkDayActivityTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func stop(_ title: String, kind: String = "ride", in minutes: Double, walk: Int = 6, wait: Int = 35) -> PlannedStop {
        PlannedStop(title: title, kind: kind, rideId: kind == "ride" ? title : nil, parkName: "MK",
                    start: now.addingTimeInterval(minutes * 60), walkMinutes: walk, waitMinutes: wait,
                    totalMinutes: walk + wait + 10)
    }

    func testStateShowsNextStopThenAndProgress() throws {
        let state = try XCTUnwrap(ParkDayActivity.state(
            stops: [stop("Seven Dwarfs", in: 10), stop("Peter Pan", in: 60)], done: 4, total: 9,
            rain: "Rain likely 3–5 PM", now: now))
        XCTAssertEqual(state.stopTitle, "Seven Dwarfs")
        XCTAssertEqual(state.stopWait, 35)
        XCTAssertTrue(state.stopDetail?.hasPrefix("Get in line ~") ?? false, state.stopDetail ?? "")
        XCTAssertTrue(state.stopDetail?.hasSuffix("6 min walk") ?? false)
        XCTAssertTrue(state.thenText?.hasPrefix("Then: Peter Pan (") ?? false)
        XCTAssertEqual(state.progressText, "4 of 9 done")
        XCTAssertEqual(state.rainText, "Rain likely 3–5 PM")
    }

    func testGoNowAndSetTimeStops() {
        let goNow = ParkDayActivity.detail(for: stop("A", in: -10, walk: 2), now: now)
        XCTAssertEqual(goNow, "Go now · 2 min walk")
        let show = ParkDayActivity.state(stops: [stop("Fireworks", kind: "show", in: 30)], done: 0, total: 3,
                                         rain: nil, now: now)
        XCTAssertNil(show?.stopWait, "no wait badge for a show")
        XCTAssertTrue(show?.stopDetail?.hasPrefix("At ") ?? false)
    }

    func testNothingNext() {
        XCTAssertNil(ParkDayActivity.state(stops: [], done: 9, total: 9, rain: nil, now: now))
    }
}
