import XCTest
import CoreLocation
@testable import ParkTrac

/// Car locator: row lists, the lot map (section + row), and learning rows from saved spots.
final class ParkingGuessTests: XCTestCase {

    /// ~111 m per 0.001° latitude; ~98 m per 0.001° longitude here
    private let base = CLLocationCoordinate2D(latitude: 28.3790, longitude: -81.5440)

    private func at(north: Double, east: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: base.latitude + north / 110_540,
                               longitude: base.longitude + east / (cos(base.latitude * .pi / 180) * 111_320))
    }

    /// A test lot "EPCOT" / "Gamora": 5 north–south row lines 20 m apart, west to east
    private var layout: ParkingLayout {
        ParkingLayout(lot: "EPCOT", section: "Gamora",
                      outline: [at(north: -60, east: -10), at(north: -60, east: 90), at(north: 60, east: 90), at(north: 60, east: -10)],
                      rowLines: (0..<5).map { i in
                          ParkingLine(a: at(north: -50, east: Double(i) * 20), b: at(north: 50, east: Double(i) * 20))
                      })
    }

    private var epcot: ParkingLot {
        ParkingLot(name: "EPCOT", groups: [.init(name: nil, sections: [ParkingSection(name: "Gamora", rows: ["801", "802", "803", "804", "805"])])])
    }

    func testRowLists() throws {
        let mk = try XCTUnwrap(ParkingLots.lot(named: "Magic Kingdom"))
        XCTAssertEqual(mk.rows(for: "Simba").first, "110")
        XCTAssertEqual(mk.rows(for: "Simba").last, "126")
        XCTAssertEqual(ParkingLots.lot(named: "Typhoon Lagoon")?.rows(for: nil).last, "Peak")
        XCTAssertEqual(ParkingLots.lot(named: "CityWalk Garages")?.rows(for: "King Kong").contains("410"), true)
        XCTAssertEqual(ParkingLots.lot(named: "Epic Universe")?.rows(for: "Valet"), [])
        XCTAssertEqual(ParkingLots.r(1...3, extra: ["Peak"]), ["1", "2", "3", "Peak"])
    }

    func testMapFindsTheSectionAndNumbersFromThePark() {
        // Park to the west → the westmost line is the lowest row
        let park = at(north: 0, east: -500)
        let result = ParkingGuess.guess(at: at(north: 10, east: 61), lots: [epcot], samples: [], presets: [layout],
                                        parkCoordinate: { _ in park })
        XCTAssertEqual(result.lot, "EPCOT")
        XCTAssertEqual(result.section, "Gamora")
        XCTAssertTrue(result.fromMap)
        XCTAssertEqual(result.row, "804")
        // Park to the east → reversed
        let flipped = ParkingGuess.guess(at: at(north: 10, east: 61), lots: [epcot], samples: [], presets: [layout],
                                         parkCoordinate: { _ in at(north: 0, east: 600) })
        XCTAssertEqual(flipped.row, "802")
    }

    func testSavedSpotsDecideTheNumbering() {
        // Someone saved row 801 at the eastmost line → rows run east to west
        let sample = ParkingSample(lot: "EPCOT", section: "Gamora", row: "801",
                                   latitude: at(north: 0, east: 80).latitude, longitude: at(north: 0, east: 80).longitude,
                                   savedAt: .distantPast)
        let result = ParkingGuess.guess(at: at(north: -20, east: 1), lots: [epcot], samples: [sample], presets: [layout],
                                        parkCoordinate: { _ in self.at(north: 0, east: -500) })
        XCTAssertEqual(result.row, "805")
    }

    func testLearnsLotsWithoutAMap() {
        let simba = ParkingLot(name: "Magic Kingdom", groups: [.init(name: nil, sections: [
            ParkingSection(name: "Simba", rows: (110...126).map(String.init)),
        ])])
        func sample(_ row: String, east: Double) -> ParkingSample {
            let c = at(north: 0, east: east)
            return ParkingSample(lot: "Magic Kingdom", section: "Simba", row: row, latitude: c.latitude,
                                 longitude: c.longitude, savedAt: .distantPast)
        }
        // Rows 110 and 120 saved 100 m apart; standing halfway → about 115
        let samples = [sample("110", east: 0), sample("120", east: 100)]
        let result = ParkingGuess.guess(at: at(north: 3, east: 50), lots: [simba], samples: samples, presets: [])
        XCTAssertEqual(result.section, "Simba", "nearest saved spot's section")
        XCTAssertFalse(result.fromMap)
        XCTAssertEqual(result.row, "115")
        // One saved spot: only when you're right next to it
        XCTAssertEqual(ParkingGuess.learnedRow(at: at(north: 0, east: 10), rows: simba.rows(for: "Simba"),
                                               samples: [sample("118", east: 0)]), "118")
        XCTAssertNil(ParkingGuess.learnedRow(at: at(north: 0, east: 90), rows: simba.rows(for: "Simba"),
                                             samples: [sample("118", east: 0)]))
    }

    func testGaragesAreNotGuessed() {
        let garage = ParkingLot(name: "CityWalk Garages", groups: [.init(name: nil, sections: [ParkingSection(name: "Jaws", rows: ["113"])])],
                                isGarage: true)
        let c = at(north: 0, east: 0)
        let sample = ParkingSample(lot: "CityWalk Garages", section: "Jaws", row: "113", latitude: c.latitude,
                                   longitude: c.longitude, savedAt: .distantPast)
        let result = ParkingGuess.guess(at: c, lots: [garage], samples: [sample], presets: [])
        XCTAssertEqual(result.section, "Jaws")
        XCTAssertNil(result.row, "GPS can't tell the level")
    }

    func testOnlyRealRowsBecomeSamples() {
        var spot = ParkingSpot(latitude: 28.41, longitude: -81.58, note: "", resortRaw: ParkGroup.disney.rawValue,
                               savedAt: .distantPast)
        spot.details = ParkingDetails(lot: "Magic Kingdom", section: "Simba", level: nil, row: "112")
        XCTAssertEqual(ParkingService.sample(from: spot)?.row, "112")
        spot.details = ParkingDetails(lot: "Magic Kingdom", section: "Simba", level: nil, row: "999")
        XCTAssertNil(ParkingService.sample(from: spot), "not one of Simba's rows")
        spot.latitude = nil
        XCTAssertNil(ParkingService.sample(from: spot))
    }

    func testPresetDataLoads() {
        XCTAssertEqual(ParkingLayouts.presets.count, 14)
        for layout in ParkingLayouts.presets {
            let lot = ParkingLots.lot(named: layout.lot)
            XCTAssertNotNil(lot, layout.lot)
            XCTAssertFalse(lot?.rows(for: layout.section).isEmpty ?? true, "\(layout.lot) \(layout.section) has rows")
            XCTAssertGreaterThan(layout.rowLines.count, 1)
        }
    }
}
