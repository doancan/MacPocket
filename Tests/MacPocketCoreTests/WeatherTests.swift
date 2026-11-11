import XCTest
@testable import MacPocketCore

final class WeatherTests: XCTestCase {
    private let location = WeatherLocation(name: "Berlin, Deutschland", latitude: 52.52, longitude: 13.405, timeZone: "Europe/Berlin")
    private let response = Data("""
    {"weather":{"currently":{"temperature":-3.5,"apparent":-7,"humidity":80,"wind-speed":4.2,"icon":{"icon":"weather-cloudy"}},
    "hourly":[{"time":1793786400,"temperature":-2,"night":1,"icon":{"icon":"weather-partlycloudy"}}],
    "forecast":[{"start":1793746800,"end":1793833200,"temperature-low":-8,"temperature-high":1}]},
    "metadata":{"provider":{"attribution":[{"link":"https://weatherkit.apple.com/legal-attribution.html"}]},"location":{"timezone":"Europe/Berlin"}}}
    """.utf8)

    func testRequestUsesChosenLocationAndJSONCredentials() throws {
        let request = try WeatherClient.request(location: location, language: "en", at: Date(timeIntervalSince1970: 12345))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["latitude"] as? String, "52.520000")
        XCTAssertEqual(body["longitude"] as? String, "13.405000")
        XCTAssertEqual(body["language"] as? String, "en")
        XCTAssertEqual(body["time"] as? String, "12345")
        // Never include the embedded identity in an assertion's printed diagnostics.
        XCTAssertTrue((body["identifier"] as? String) == WeatherAPIConfiguration.deviceIdentifier)
    }

    func testInvalidCoordinatesCannotLeaveTheMachine() {
        for coordinate in [Double.nan, .infinity, 91, -91] {
            let place = WeatherLocation(name: "Invalid", latitude: coordinate, longitude: 0)
            XCTAssertThrowsError(try WeatherClient.request(location: place, language: "tr")) { XCTAssertEqual($0 as? WeatherError, .invalidLocation) }
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

    func testDecodesProviderUnitsForecastAndTimeZone() throws {
        let at = Date(timeIntervalSince1970: 12345)
        let weather = try WeatherSnapshot.decode(response, location: location, at: at)
        XCTAssertEqual(weather.current.temperature, -3.5)
        XCTAssertEqual(weather.current.windSpeed, 4.2)
        XCTAssertEqual(weather.hourly.first?.symbol, "cloud.moon.fill")
        XCTAssertEqual(weather.forecast.first?.low, -8)
        XCTAssertEqual(weather.forecast.first?.high, 1)
        XCTAssertEqual(weather.timeZone.identifier, "Europe/Berlin")
        XCTAssertEqual(weather.fetchedAt, at)
        XCTAssertEqual(weather.location, location)
        XCTAssertEqual(weather.attributions.first?.title, "Apple Weather")
    }

    func testServerErrorsAreNotRenderedAsZeroDegrees() {
        for code in ["notfound", "expired", "limited", "locationnotfound"] {
            let data = Data("{\"error\":{\"code\":\"\(code)\"}}".utf8)
            XCTAssertThrowsError(try WeatherSnapshot.decode(data, location: location)) { XCTAssertEqual($0 as? WeatherError, .server(code)) }
        }
        for json in ["{}", "{\"weather\":{\"currently\":{}}}", "{\"weather\":{\"currently\":{\"temperature\":999}}}", "invalid"] {
            XCTAssertThrowsError(try WeatherSnapshot.decode(Data(json.utf8), location: location)) { XCTAssertEqual($0 as? WeatherError, .invalidResponse) }
        }
    }

    func testOptionalForecastAndUntrustedAttribution() throws {
        let data = Data("""
        {"weather":{"currently":{"temperature":0}},"metadata":{"provider":{"attribution":[{"link":"http://example.com"}]}}}
        """.utf8)
        let weather = try WeatherSnapshot.decode(data, location: location)
        XCTAssertTrue(weather.hourly.isEmpty)
        XCTAssertTrue(weather.forecast.isEmpty)
        XCTAssertNil(weather.attributions.first?.url)
        XCTAssertEqual(weather.timeZone.identifier, location.timeZone)
    }

    func testWeatherMenuReadingWorksWithoutSystemSnapshot() throws {
        let weather = try WeatherSnapshot.decode(response, location: location)
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
