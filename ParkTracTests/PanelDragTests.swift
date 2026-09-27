import XCTest
@testable import ParkTrac

/// Wait Times bottom panel: drag/flick anywhere on its header to expand or collapse.
final class PanelDragTests: XCTestCase {

    func testDragUpExpandsAndDownCollapses() {
        XCTAssertTrue(PanelDrag.shouldExpand(wasExpanded: false, translation: -80, predicted: -90))
        XCTAssertFalse(PanelDrag.shouldExpand(wasExpanded: true, translation: 80, predicted: 90))
    }

    func testShortDragKeepsState() {
        XCTAssertFalse(PanelDrag.shouldExpand(wasExpanded: false, translation: -20, predicted: -25))
        XCTAssertTrue(PanelDrag.shouldExpand(wasExpanded: true, translation: 20, predicted: 25))
    }

    func testQuickFlickCounts() {
        // Moved only a little, but flicked hard upward
        XCTAssertTrue(PanelDrag.shouldExpand(wasExpanded: false, translation: -25, predicted: -200))
    }

    func testHeightFollowsFingerWithinBounds() {
        XCTAssertEqual(PanelDrag.height(expanded: false, drag: -100, collapsed: 320, full: 700), 420)
        XCTAssertEqual(PanelDrag.height(expanded: false, drag: -900, collapsed: 320, full: 700), 700)
        XCTAssertEqual(PanelDrag.height(expanded: false, drag: 500, collapsed: 320, full: 700), 192, accuracy: 0.001)
        XCTAssertEqual(PanelDrag.height(expanded: true, drag: 0, collapsed: 320, full: 700), 700)
    }
}
