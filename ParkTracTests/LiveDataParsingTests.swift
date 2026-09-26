import XCTest
@testable import ParkTrac

/// Decoding themeparks.wiki payloads: Lightning Lane queues and schedule event names.
final class LiveDataParsingTests: XCTestCase {

    private func entry(_ json: String) throws -> LiveDataEntry {
        try JSONDecoder().decode(LiveDataEntry.self, from: Data(json.utf8))
    }

    private func queue(_ json: String) throws -> LightningLaneInfo? {
        LightningLaneInfo(try JSONDecoder().decode(ReturnTimeQueue.self, from: Data(json.utf8)))
    }

    func testMultiAndSinglePassDecode() throws {
        let live = try entry("""
        {"id":"slinky","name":"Slinky Dog Dash","entityType":"ATTRACTION","status":"OPERATING",
         "queue":{"STANDBY":{"waitTime":70},
                  "RETURN_TIME":{"state":"AVAILABLE","returnStart":"2026-09-26T13:35:00-04:00","returnEnd":"2026-09-26T14:35:00-04:00"},
                  "PAID_RETURN_TIME":{"state":"AVAILABLE","returnStart":"2026-09-26T11:05:00-04:00","returnEnd":null,
                                      "price":{"amount":1500,"currency":"USD","formatted":"$15.00"}}}}
        """)
        let ride = DisplayRide(live: live, parkId: "hs", location: nil)

        XCTAssertEqual(ride.waitMinutes, 70)
        let multi = try XCTUnwrap(ride.multiPass)
        XCTAssertTrue(multi.isAvailable)
        XCTAssertEqual(multi.returnStart, ISO8601DateFormatter().date(from: "2026-09-26T17:35:00Z"))
        XCTAssertNotNil(multi.returnEnd)
        XCTAssertNil(multi.price)

        let single = try XCTUnwrap(ride.singlePass)
        XCTAssertEqual(single.price, "$15.00")
        XCTAssertNil(single.returnEnd)
    }

    func testNoLightningLaneQueues() throws {
        let live = try entry("""
        {"id":"x","name":"Carousel","entityType":"ATTRACTION","status":"OPERATING","queue":{"STANDBY":{"waitTime":5}}}
        """)
        let ride = DisplayRide(live: live, parkId: "mk", location: nil)
        XCTAssertNil(ride.multiPass)
        XCTAssertNil(ride.singlePass)
    }

    func testStates() throws {
        XCTAssertEqual(try queue(#"{"state":"TEMP_FULL"}"#)?.state, .temporarilyFull)
        XCTAssertEqual(try queue(#"{"state":"FINISHED"}"#)?.state, .soldOut)
        XCTAssertEqual(try queue(#"{"state":"SOMETHING_NEW"}"#)?.state, .unknown)
        // Available but no time → not bookable
        XCTAssertEqual(try queue(#"{"state":"AVAILABLE"}"#)?.isAvailable, false)
    }

    func testShortText() throws {
        XCTAssertEqual(try queue(#"{"state":"FINISHED"}"#)?.shortText, "LL sold out")
        XCTAssertEqual(try queue(#"{"state":"TEMP_FULL"}"#)?.shortText, "LL full for now")
        let available = try queue(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:35:00-04:00"}"#)
        XCTAssertTrue(available?.shortText.hasPrefix("LL ") == true)
    }

    func testPriceFromCentsWhenNotFormatted() throws {
        let info = try queue(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:35:00Z","price":{"amount":1500,"currency":"USD"}}"#)
        XCTAssertTrue(info?.price?.contains("15") == true, info?.price ?? "nil")
    }

    func testFractionalSecondDates() throws {
        let info = try queue(#"{"state":"AVAILABLE","returnStart":"2026-09-26T13:35:00.000Z"}"#)
        XCTAssertNotNil(info?.returnStart)
    }

    func testClosedCatalogRideHasNoLightningLane() {
        let ride = DisplayRide(catalogId: "c", name: "Closed Ride", parkId: "p", location: nil)
        XCTAssertNil(ride.multiPass)
        XCTAssertEqual(ride.spokenStatus, "Closed")
    }

    // MARK: Schedule event names

    func testTicketedEventName() throws {
        let day = try JSONDecoder().decode(ParkScheduleDay.self, from: Data("""
        {"date":"2026-10-02","type":"TICKETED_EVENT","openingTime":"2026-10-02T19:00:00-04:00",
         "closingTime":"2026-10-03T00:00:00-04:00","description":"Mickey's Not-So-Scary Halloween Party"}
        """.utf8))
        XCTAssertEqual(day.eventName, "Mickey's Not-So-Scary Halloween Party")
    }

    func testBlankOrMissingEventName() throws {
        let blank = try JSONDecoder().decode(ParkScheduleDay.self, from: Data(#"{"date":"2026-10-02","type":"TICKETED_EVENT","description":"  "}"#.utf8))
        XCTAssertNil(blank.eventName)
        let missing = try JSONDecoder().decode(ParkScheduleDay.self, from: Data(#"{"date":"2026-10-02","type":"OPERATING"}"#.utf8))
        XCTAssertNil(missing.eventName)
    }
}

/// Ride GPS decoding must survive odd entries (Japan parks showed rides but no pins).
final class AttractionDecodingTests: XCTestCase {

    func testOneBadAttractionDoesNotDropTheRest() throws {
        let json = """
        {"id":"tdl","name":"Tokyo Disneyland","entityType":"PARK","children":[
          {"id":"a","name":"Big Thunder Mountain","entityType":"ATTRACTION","location":{"latitude":35.6341,"longitude":139.8785}},
          {"id":"b","name":"Broken","location":{"latitude":1}},
          null,
          {"id":"c","name":"Pooh's Hunny Hunt","entityType":"ATTRACTION","location":{"latitude":"35.6308","longitude":"139.8812"}},
          {"id":"d","name":"No GPS","entityType":"ATTRACTION","location":{"latitude":null,"longitude":null}},
          {"id":"e","name":"Zero","entityType":"ATTRACTION","location":{"latitude":0,"longitude":0}}
        ]}
        """
        let response = try JSONDecoder().decode(ParkChildrenResponse.self, from: Data(json.utf8))
        // "b" lacks entityType and null isn't an entity → skipped; the rest survive
        XCTAssertEqual(response.children.map(\.id), ["a", "c", "d", "e"])
        XCTAssertNotNil(response.children[0].coordinate)
        XCTAssertEqual(try XCTUnwrap(response.children[1].coordinate).latitude, 35.6308, accuracy: 0.0001, "string coords")
        XCTAssertNil(response.children[2].coordinate, "null coords")
        XCTAssertNil(response.children[3].coordinate, "0,0 placeholder")
    }

    func testParkChildrenAreLossyToo() throws {
        let json = """
        {"id":"tdr","name":"Tokyo Disney Resort","entityType":"DESTINATION","children":[
          {"id":"p1","name":"Tokyo Disneyland","entityType":"PARK"},
          {"id":"p2","name":"Tokyo DisneySea","entityType":"PARK","location":{"latitude":35.6267,"longitude":139.8851}},
          {"broken":true}
        ]}
        """
        let response = try JSONDecoder().decode(DestinationChildrenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.children.map(\.id), ["p1", "p2"])
    }
}
