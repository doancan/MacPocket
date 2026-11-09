import XCTest
@testable import MacPocketCore

private final class WeatherHTTPFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        let status = host.contains("visualcrossing") ? 429 : host.contains("weatherapi.com") ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Expires": "Mon, 09 Nov 2026 18:00:00 GMT"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"current":{"temperature_2m":12}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WeatherProviderTests: XCTestCase {
    private let location = WeatherLocation(name: "İstanbul", latitude: 41.0082345, longitude: 28.9784567, timeZone: "Europe/Istanbul")
    private let now = Date(timeIntervalSince1970: 1_794_182_400) // 2026-11-09 08:00 UTC
    private func decode(_ json: String, _ source: WeatherSource, extra: String? = nil) throws -> WeatherSnapshot {
        try WeatherProviderClient.decode([Data(json.utf8)] + (extra.map { [Data($0.utf8)] } ?? []), source: source, location: location, at: now)
    }

    func testBasketPersistenceMigrationAndLastSourceProtection() throws {
        var basket = WeatherBasket()
        XCTAssertEqual(basket.active, .visualCrossing)
        basket.select(.gfs); basket.include(.gfs, included: false)
        XCTAssertTrue(basket.sources.contains(basket.active))
        basket = WeatherBasket(sources: [.metNorway], active: .metNorway)
        basket.include(.metNorway, included: false)
        XCTAssertEqual(basket.sources, [.metNorway])
        XCTAssertEqual(WeatherBasket.restored(try JSONEncoder().encode(basket), hasExistingLocation: true), basket)
        XCTAssertEqual(WeatherBasket.restored(nil, hasExistingLocation: true).active, .istatLegacy)
        XCTAssertEqual(WeatherBasket.restored(Data("invalid".utf8), hasExistingLocation: false).active, .visualCrossing)
    }
    func testCatalogSeparatesPublicSourcesFromLegacyAndPaidEndpoints() throws {
        XCTAssertEqual(WeatherSource.catalog.count, 11)
        XCTAssertFalse(WeatherSource.catalog.contains(.istatLegacy))
        for source in WeatherSource.catalog {
            let requests = try WeatherProviderClient.requests(source: source, location: location, language: "tr", apiKey: "owned-fixture")
            XCTAssertFalse(requests.isEmpty)
            for request in requests {
                XCTAssertEqual(request.url?.scheme, "https")
                XCTAssertNotEqual(request.url?.host, WeatherAPIConfiguration.endpoint.host)
                XCTAssertFalse(request.url!.path.contains("onecall"))
                XCTAssertFalse(request.url!.path.contains("minutely"))
                XCTAssertNil(request.httpBody)
            }
        }
        let openWeather = try WeatherProviderClient.requests(source: .openWeather, location: location, language: "tr", apiKey: "owned-fixture")
        XCTAssertEqual(openWeather.map { $0.url!.path }, ["/data/2.5/weather", "/data/2.5/forecast"])
    }
    func testRequestsValidateCoordinatesAndCredentialsBeforeTransport() throws {
        let invalid = WeatherLocation(name: "bad", latitude: .nan, longitude: 0)
        for source in WeatherSource.catalog {
            XCTAssertThrowsError(try WeatherProviderClient.requests(source: source, location: invalid, language: "tr", apiKey: "owned-fixture"))
            if source.requiresAPIKey {
                for key in [nil, "", "invalid/key", "invalid?key", "line\nbreak", String(repeating: "a", count: 513)] as [String?] {
                    XCTAssertThrowsError(try WeatherProviderClient.requests(source: source, location: location, language: "tr", apiKey: key))
                }
            }
        }
        let met = try XCTUnwrap(WeatherProviderClient.requests(source: .metNorway, location: location, language: "tr").first)
        let query = URLComponents(url: met.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "lat" }?.value, "41.0082")
        XCTAssertEqual(query.first { $0.name == "lon" }?.value, "28.9785")
        XCTAssertTrue(met.value(forHTTPHeaderField: "User-Agent")!.contains("MacPocket"))
        XCTAssertEqual(met.value(forHTTPHeaderField: "Accept-Encoding"), "gzip")
        for source in [WeatherSource.ecmwf, .ecmwfAI, .gfs, .icon] {
            let request = try WeatherProviderClient.requests(source: source, location: location, language: "en")[0]
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "models" }?.value, source.model)
        }
    }
    func testOpenMeteoDecodesUnitsNightAndMissingValues() throws {
        let snapshot = try decode(#"{"timezone":"Europe/Istanbul","current":{"temperature_2m":12,"apparent_temperature":10,"wind_speed_10m":5,"relative_humidity_2m":70,"weather_code":0,"is_day":0},"hourly":{"time":["2026-11-09T21:00","2026-11-09T22:00"],"temperature_2m":[11,null],"weather_code":[0,2],"is_day":[0,0]},"daily":{"time":["2026-11-09"],"temperature_2m_min":[5],"temperature_2m_max":[14],"weather_code":[3]}}"#, .ecmwf)
        XCTAssertEqual(snapshot.current.windSpeed, 5)
        XCTAssertEqual(snapshot.current.apparent, 10)
        XCTAssertEqual(snapshot.symbol, "moon.stars.fill")
        XCTAssertEqual(snapshot.hourly.count, 1)
        XCTAssertEqual(snapshot.hourly[0].symbol, "moon.stars.fill")
        XCTAssertEqual(snapshot.forecast.first?.low, 5)
        XCTAssertEqual(snapshot.source, .ecmwf)
        XCTAssertEqual(snapshot.attributions.map(\.title), ["Open-Meteo", "ECMWF"])
    }
    func testVisualCrossingConvertsWindAndPreservesOptionalFields() throws {
        let value = try decode(#"{"timezone":"Europe/Istanbul","currentConditions":{"temp":12,"windspeed":18,"icon":"partly-cloudy-night"},"days":[{"datetimeEpoch":1794171600,"tempmin":8,"tempmax":15,"hours":[{"datetimeEpoch":1794200000,"temp":13,"icon":"clear-night"}]}]}"#, .visualCrossing)
        XCTAssertEqual(value.current.windSpeed, 5)
        XCTAssertNil(value.current.humidity)
        XCTAssertNil(value.current.apparent)
        XCTAssertEqual(value.hourly.first?.symbol, "moon.stars.fill")
        XCTAssertEqual(value.attributions.first?.title, "Visual Crossing")
        XCTAssertEqual(value.forecast.first?.high, 15)
    }
    func testMETUsesLatestSampleNotFutureAndDoesNotInventFeelsLike() throws {
        let value = try decode(#"{"properties":{"timeseries":[{"time":"2026-11-09T07:00:00Z","data":{"instant":{"details":{"air_temperature":7,"wind_speed":4}},"next_1_hours":{"summary":{"symbol_code":"fair_night"}}}},{"time":"2026-11-09T09:00:00Z","data":{"instant":{"details":{"air_temperature":99}}}}]}}"#, .metNorway)
        XCTAssertEqual(value.current.temperature, 7)
        XCTAssertEqual(value.current.windSpeed, 4)
        XCTAssertNil(value.current.apparent)
        XCTAssertEqual(value.symbol, "cloud.moon.fill")
        XCTAssertEqual(value.attributions.first?.title, "MET Norway")
    }
    func testKeyedAdaptersNormalizeProviderSpecificFields() throws {
        let weatherAPI = try decode(#"{"current":{"temp_c":10,"wind_kph":18,"humidity":70,"condition":{"code":1213},"is_day":1},"forecast":{"forecastday":[{"date":"2026-11-09","day":{"mintemp_c":2,"maxtemp_c":12,"condition":{"code":1000}},"hour":[{"time_epoch":1794200000,"temp_c":11,"is_day":0,"condition":{"code":1000}}]}]}}"#, .weatherAPI)
        XCTAssertEqual(weatherAPI.current.windSpeed, 5); XCTAssertEqual(weatherAPI.symbol, "cloud.snow.fill")
        XCTAssertEqual(weatherAPI.hourly.first?.symbol, "moon.stars.fill"); XCTAssertEqual(weatherAPI.forecast.first?.high, 12)
        let pirate = try decode(#"{"currently":{"temperature":10,"windSpeed":5,"humidity":0.7,"icon":"clear-day"},"hourly":{"data":[{"time":1794200000,"temperature":9,"icon":"clear-night"}]},"daily":{"data":[{"time":1794171600,"temperatureLow":2,"temperatureHigh":12}]}}"#, .pirateWeather)
        XCTAssertEqual(pirate.current.humidity, 70); XCTAssertEqual(pirate.current.windSpeed, 5)
        XCTAssertEqual(pirate.forecast.first?.low, 2)
        let open = try decode(#"{"main":{"temp":10,"feels_like":8,"humidity":70},"wind":{"speed":5},"weather":[{"main":"Clear","icon":"01n"}]}"#, .openWeather,
            extra: #"{"list":[{"dt":1794300000,"main":{"temp":13},"weather":[{"main":"Rain","icon":"10d"}]}]}"#)
        XCTAssertEqual(open.current.windSpeed, 5); XCTAssertEqual(open.symbol, "moon.stars.fill")
        XCTAssertEqual(open.hourly.first?.temperature, 13)
        let tomorrow = try decode(#"{"timelines":{"hourly":[{"time":"2026-11-09T07:00:00Z","values":{"temperature":10,"temperatureApparent":8,"windSpeed":5,"weatherCode":4001}}],"daily":[{"time":"2026-11-10T00:00:00Z","values":{"temperatureMin":2,"temperatureMax":12,"weatherCodeMax":1000}}]}}"#, .tomorrow)
        XCTAssertEqual(tomorrow.current.apparent, 8); XCTAssertEqual(tomorrow.current.windSpeed, 5)
        XCTAssertEqual(tomorrow.symbol, "cloud.rain.fill"); XCTAssertEqual(tomorrow.forecast.first?.high, 12)
    }
    func testMalformedMissingOrBooleanTemperatureNeverBecomesZero() throws {
        for json in ["{}", #"{"current":{"temperature_2m":null}}"#, #"{"current":{"temperature_2m":true}}"#, #"{"current":{"temperature_2m":999}}"#] {
            XCTAssertThrowsError(try decode(json, .openMeteo))
        }
        XCTAssertThrowsError(try decode(#"{"error":{"code":2008}}"#, .weatherAPI))
        let zero = try decode(#"{"current":{"temperature_2m":0}}"#, .openMeteo)
        XCTAssertEqual(zero.current.temperature, 0)
        XCTAssertTrue(zero.hourly.isEmpty); XCTAssertTrue(zero.forecast.isEmpty)
        XCTAssertThrowsError(try decode(#"{"main":{"temp":10}}"#, .openWeather))
    }
    func testTransportSanitizesAuthAndRateErrorsAndHonorsExpiry() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [WeatherHTTPFixture.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        for (source, expected) in [(WeatherSource.visualCrossing, WeatherSourceError.rateLimited), (.weatherAPI, .authentication)] {
            do {
                _ = try await WeatherProviderClient.fetch(source: source, location: location, language: "en", apiKey: "owned-fixture", session: session)
                XCTFail("HTTP error accepted")
            } catch { XCTAssertEqual(error as? WeatherSourceError, expected); XCTAssertFalse(error.localizedDescription.contains("owned-fixture")) }
        }
        let value = try await WeatherProviderClient.fetch(source: .openMeteo, location: location, language: "tr", session: session, at: now)
        XCTAssertGreaterThan(try XCTUnwrap(value.nextRefreshAt), now.addingTimeInterval(3_600))
        XCTAssertEqual(value.current.temperature, 12)
    }
    func testAnonymousProvidersLiveWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MACPOCKET_WEATHER_LIVE"] == "1" else { throw XCTSkip("Opt-in public weather API acceptance") }
        var report: [[String: Any]] = []
        for source in WeatherSource.catalog where !source.requiresAPIKey {
            do {
                let value = try await WeatherProviderClient.fetch(source: source, location: location, language: "tr")
                report.append(["source":source.rawValue,"passed":true,"hours":value.hourly.count,"days":value.forecast.count,"temperature":value.current.temperature ?? NSNull()])
            } catch { report.append(["source":source.rawValue,"passed":false,"error":error.localizedDescription]) }
        }
        let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/weather-basket/live-report.json")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
        for entry in report { XCTAssertEqual(entry["passed"] as? Bool, true, "\(entry["source"] ?? "unknown"): \(entry["error"] ?? "")") }
    }
}
