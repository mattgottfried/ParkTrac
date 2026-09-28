import XCTest
@testable import ParkTrac

/// Past weather for a logged visit day, from Open-Meteo's historical archive.
final class HistoricalWeatherTests: XCTestCase {
    func testParsesTheRequestedDate() {
        let json = """
        {"daily":{"time":["2026-10-09","2026-10-10"],"weathercode":[3,61],
        "temperature_2m_max":[88.5,79.0],"precipitation_sum":[0.0,0.42]}}
        """
        let day = HistoricalWeather.parse(Data(json.utf8), dateKey: "2026-10-10")
        XCTAssertEqual(day?.weatherCode, 61)
        XCTAssertEqual(day?.highF, 79.0)
        XCTAssertEqual(day?.precipitationInches, 0.42)
    }

    func testNilWhenTheDateIsMissing() {
        let json = #"{"daily":{"time":["2026-10-09"],"weathercode":[3],"temperature_2m_max":[88.5]}}"#
        XCTAssertNil(HistoricalWeather.parse(Data(json.utf8), dateKey: "2026-10-10"))
    }

    func testNilOnJunk() {
        XCTAssertNil(HistoricalWeather.parse(Data("nope".utf8), dateKey: "2026-10-10"))
    }

    func testDescribeCommonCodes() {
        XCTAssertEqual(HistoricalWeather.describe(0).text, "Clear")
        XCTAssertEqual(HistoricalWeather.describe(61).text, "Rain")
        XCTAssertEqual(HistoricalWeather.describe(95).text, "Thunderstorms")
        XCTAssertEqual(HistoricalWeather.describe(999).text, "Weather", "unknown codes fall back gracefully")
    }
}
