import XCTest
@testable import MacPocketCore

final class WeatherTests: XCTestCase {
    private let location = WeatherLocation(name: "Berlin, Deutschland", latitude: 52.52, longitude: 13.405, timeZone: "Europe/Berlin")
    private func snapshot(temperature: Double = -3.5, apparent: Double = -7) throws -> WeatherSnapshot {
        let conditions = WeatherConditions(temperature: temperature, apparent: apparent, humidity: nil, pressure: nil,
                                           windSpeed: nil, conditions: nil, icon: nil)
        return WeatherSnapshot(location: location, current: conditions, hourly: [], forecast: [], attributions: [],
                               fetchedAt: Date(timeIntervalSince1970: 12345), serverTimeZone: nil)
    }

    func testInvalidCoordinatesCannotLeaveTheMachine() {
        for coordinate in [Double.nan, .infinity, 91, -91] {
            let place = WeatherLocation(name: "Invalid", latitude: coordinate, longitude: 0)
            XCTAssertThrowsError(try WeatherProviderClient.requests(source: .openMeteo, location: place, language: "tr")) { XCTAssertEqual($0 as? WeatherError, .invalidLocation) }
        }
        XCTAssertFalse(WeatherLocation(name: " ", latitude: 0, longitude: 0).isValid)
        XCTAssertFalse(WeatherLocation(name: "Invalid", latitude: 0, longitude: 181).isValid)
    }

    func testSelectedPlaceSurvivesStorageRoundTrip() throws {
        let stored = try JSONEncoder().encode(location)
        let restored = try JSONDecoder().decode(WeatherLocation.self, from: stored)
        XCTAssertEqual(restored, location)
        XCTAssertTrue(restored.isValid)
    }

    func testWeatherMenuReadingWorksWithoutSystemSnapshot() throws {
        let weather = try snapshot()
        var settings = MenuBarModuleSettings.defaults(for: .weather)
        var reading = MenuBarFormatter.reading(.weather, settings: settings, snapshot: nil, weather: weather)
        XCTAssertEqual(reading.magnitude, -3.5)
        XCTAssertTrue(reading.lines[0].hasSuffix("°"))
        XCTAssertTrue(reading.accessibility.contains(location.name))
        settings.value = .weatherApparent
        reading = MenuBarFormatter.reading(.weather, settings: settings, snapshot: nil, weather: weather)
        XCTAssertEqual(reading.magnitude, -7)
        XCTAssertNil(reading.thresholdValue)
        let pending = MenuBarFormatter.reading(.weather, settings: settings, snapshot: nil)
        XCTAssertNil(pending.magnitude)
        XCTAssertEqual(pending.lines, ["—°"])
        settings.style = .pie
        XCTAssertEqual(settings.normalized(for: .weather).style, .value)
    }

    func testLocationDisplayNameDropsARepeatedPlace() {
        func name(_ value: String) -> String { WeatherLocation(name: value, latitude: 1, longitude: 1).displayName }
        XCTAssertEqual(name("Ankara Ankara, Türkiye"), "Ankara, Türkiye")
        XCTAssertEqual(name("İzmir İzmir, Türkiye"), "İzmir, Türkiye")
        XCTAssertEqual(name("New York New York, ABD"), "New York, ABD")
        XCTAssertEqual(name("Kadıköy İstanbul, Türkiye"), "Kadıköy İstanbul, Türkiye")
        XCTAssertEqual(name("Paris"), "Paris")
    }
}
