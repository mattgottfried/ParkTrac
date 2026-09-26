import XCTest
@testable import ParkTrac

/// AAP / DAS return-time rules (AccessPass.returnDelayMinutes).
final class ReturnRulesTests: XCTestCase {

    // Universal AAP: posted < 30 → immediate; 30+ → posted − 15

    func testAAPUnderThirtyIsImmediate() {
        for wait in [0, 5, 15, 29] {
            XCTAssertEqual(AccessPass.aap.returnDelayMinutes(postedWait: wait), 0, "posted \(wait)")
        }
    }

    func testAAPThirtyOrMoreIsWaitMinusFifteen() {
        XCTAssertEqual(AccessPass.aap.returnDelayMinutes(postedWait: 30), 15)
        XCTAssertEqual(AccessPass.aap.returnDelayMinutes(postedWait: 45), 30)
        XCTAssertEqual(AccessPass.aap.returnDelayMinutes(postedWait: 120), 105)
    }

    func testAAPNoPostedWaitIsImmediate() {
        XCTAssertEqual(AccessPass.aap.returnDelayMinutes(postedWait: nil), 0)
        XCTAssertEqual(AccessPass.aap.returnDelayMinutes(postedWait: -5), 0)
    }

    func testDASUsesPostedWait() {
        XCTAssertEqual(AccessPass.das.returnDelayMinutes(postedWait: 20), 20)
        XCTAssertEqual(AccessPass.das.returnDelayMinutes(postedWait: 60), 60)
    }

    func testEstimatedReturnAddsDelay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AccessPass.aap.estimatedReturn(postedWait: 45, from: now),
                       now.addingTimeInterval(30 * 60))
        XCTAssertEqual(AccessPass.aap.estimatedReturn(postedWait: 20, from: now), now)
    }

    func testReturnPhrase() {
        XCTAssertEqual(AccessPass.aap.returnPhrase(postedWait: 20), "right away")
        XCTAssertTrue(AccessPass.aap.returnPhrase(postedWait: 60).hasPrefix("around "))
    }
}
