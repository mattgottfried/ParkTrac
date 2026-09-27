import XCTest
@testable import ParkTrac

/// Changing a plan after it's made: less walking, areas, and the Apple Intelligence refine prompt.
final class PlanRefineTests: XCTestCase {

    /// Rides on a line running east, ~100 m apart (≈ 2 min walk each)
    private func ride(_ id: String, east steps: Double) -> PlanRide {
        PlanRide(id: id, name: id, parkName: "P", latitude: 28.4, longitude: -81.5 + steps * 0.001, waitByHour: [:])
    }

    func testLessWalkingStopsTheZigZag() {
        let a = ride("A", east: 0), b = ride("B", east: 1), c = ride("C", east: 2), d = ride("D", east: 3)
        let zigzag = [a, d, b, c]
        let tidy = PlanOrdering.lessWalking(zigzag)
        XCTAssertEqual(tidy.map(\.id), ["A", "B", "C", "D"], "keeps the first ride, then walks in one direction")
        XCTAssertLessThan(PlanOrdering.totalWalk(tidy), PlanOrdering.totalWalk(zigzag))
    }

    func testRidesWithoutALocationGoLast() {
        let a = ride("A", east: 0), b = ride("B", east: 1), c = ride("C", east: 2)
        let unknown = PlanRide(id: "X", name: "X", parkName: "P", waitByHour: [:])
        XCTAssertEqual(PlanOrdering.lessWalking([a, unknown, c, b]).map(\.id), ["A", "B", "C", "X"])
    }

    func testMustDosFirst() {
        let a = ride("A", east: 0), b = ride("B", east: 1), c = ride("C", east: 2)
        XCTAssertEqual(PlanOrdering.mustDosFirst([a, b, c], mustDo: ["C"]).map(\.id), ["C", "A", "B"])
    }

    func testWantsLessWalking() {
        XCTAssertTrue(PlanOrdering.wantsLessWalking("I'd rather do rides close to each other"))
        XCTAssertTrue(PlanOrdering.wantsLessWalking("too much back and forth"))
        XCTAssertFalse(PlanOrdering.wantsLessWalking("TRON last please"))
    }

    func testAreasGroupNearbyRides() {
        // A and B next to each other; C ~1 km away
        let areas = PlanAreas.assign([ride("A", east: 0), ride("B", east: 1), ride("C", east: 10)])
        XCTAssertEqual(areas["A"], "A")
        XCTAssertEqual(areas["B"], "A")
        XCTAssertEqual(areas["C"], "B")
    }

    func testRefinePromptCarriesThePlanAndTheAsks() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let at9 = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!
        let input = PlannerAI.PlanInput(
            rides: [.init(name: "Stardust Racers", waitsByHour: [9: 40], isMustDo: true, area: "B")],
            shows: [], dining: [], start: at9, end: nil, notes: "")
        let text = PlannerAI.refinePrompt(input, currentOrder: ["Stardust Racers", "Fyre Drill"], walkMinutes: 42,
                                          requests: ["Less walking", "keep rides close together"], calendar: cal)
        XCTAssertTrue(text.contains("- Stardust Racers (Must-Do) [area B]: expected wait"), text)
        XCTAssertTrue(text.contains("about 42 minutes of walking"))
        XCTAssertTrue(text.contains("1. Stardust Racers\n2. Fyre Drill"))
        XCTAssertTrue(text.contains("- keep rides close together"))
    }
}
