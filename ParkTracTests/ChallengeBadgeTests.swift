import XCTest
@testable import ParkTrac

/// Lifetime / multi-trip challenges — unlike Park Bingo / Resort Bingo, these never reset and are
/// evaluated from logged history alone.
final class ChallengeBadgeTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func log(_ name: String, resort: String = "Walt Disney World", park: String = "Magic Kingdom", on date: Date = Date()) -> RideLog {
        RideLog(rideId: name, rideName: name, parkId: "p", parkName: park, resort: resort, riddenAt: date)
    }

    // MARK: Coaster Collector

    func testCoasterCollectorNeedsEveryResortCoaster() {
        let allDisneyCoasters: [RideLog] = [
            "Space Mountain", "Big Thunder Mountain Railroad", "Seven Dwarfs Mine Train",
            "Expedition Everest", "TRON Lightcycle / Run", "Guardians of the Galaxy: Cosmic Rewind",
            "Rock 'n' Roller Coaster Starring Aerosmith", "Slinky Dog Dash",
        ].map { log($0) }
        XCTAssertTrue(LifetimeChallengeRules.hasCoasterCollection(rides: allDisneyCoasters.map { (resort: $0.resort, rideName: $0.rideName) }))
    }

    func testCoasterCollectorFalseWhenOneMissing() {
        let missingOne: [RideLog] = ["Space Mountain", "Big Thunder Mountain Railroad"].map { log($0) }
        XCTAssertFalse(LifetimeChallengeRules.hasCoasterCollection(rides: missingOne.map { (resort: $0.resort, rideName: $0.rideName) }))
    }

    // MARK: World Traveler

    func testWorldTravelerNeedsAllFourResorts() {
        let resorts = ["Walt Disney World", "Universal Orlando", "Tokyo Disney Resort", "Universal Studios Japan"]
        XCTAssertTrue(LifetimeChallengeRules.isWorldTraveler(resorts: resorts))
    }

    func testWorldTravelerFalseWithOnlyThreeResorts() {
        let resorts = ["Walt Disney World", "Universal Orlando", "Tokyo Disney Resort"]
        XCTAssertFalse(LifetimeChallengeRules.isWorldTraveler(resorts: resorts))
    }

    // MARK: Park Completionist

    func testParkCompletionistMatchesBySubstring() {
        // Real API text might say "Disney's Hollywood Studios" rather than the bare keyword.
        let parks = ["Magic Kingdom Park", "Epcot", "Disney's Hollywood Studios", "Disney's Animal Kingdom Theme Park"]
        XCTAssertTrue(ParkCompletionist.completed(parkNames: parks, resort: "Walt Disney World"))
    }

    func testParkCompletionistFalseWhenAParkIsMissing() {
        let parks = ["Magic Kingdom", "Epcot"]
        XCTAssertFalse(ParkCompletionist.completed(parkNames: parks, resort: "Walt Disney World"))
    }

    func testNoParkCompletionistRosterForAnUnknownResort() {
        XCTAssertFalse(ParkCompletionist.completed(parkNames: ["Anything"], resort: "Somewhere Else"))
    }

    func testHasCompletedAParkInOneTripNeedsAllFourInTheSameTrip() {
        // Same trip (consecutive days): all 4 WDW parks
        let trip = [
            log("A", park: "Magic Kingdom", on: day(2026, 1, 1)),
            log("B", park: "Epcot", on: day(2026, 1, 2)),
            log("C", park: "Hollywood Studios", on: day(2026, 1, 3)),
            log("D", park: "Animal Kingdom", on: day(2026, 1, 4)),
        ]
        XCTAssertTrue(LifetimeChallengeRules.hasCompletedAParkInOneTrip(rides: trip))
    }

    func testHasCompletedAParkInOneTripFalseAcrossSeparateTrips() {
        // A long gap splits these into two trips, each missing parks
        let rides = [
            log("A", park: "Magic Kingdom", on: day(2025, 1, 1)),
            log("B", park: "Epcot", on: day(2025, 1, 2)),
            log("C", park: "Hollywood Studios", on: day(2026, 6, 1)),
            log("D", park: "Animal Kingdom", on: day(2026, 6, 2)),
        ]
        XCTAssertFalse(LifetimeChallengeRules.hasCompletedAParkInOneTrip(rides: rides))
    }

    // MARK: Penny Pincher

    func testPennyPincherMarksAndStaysMarked() {
        UserDefaults.standard.removeObject(forKey: "pennyPincherBrokeEven")
        XCTAssertFalse(PennyPincher.hasBrokenEven())
        PennyPincher.markBrokeEven()
        XCTAssertTrue(PennyPincher.hasBrokenEven())
        UserDefaults.standard.removeObject(forKey: "pennyPincherBrokeEven")
    }
}
