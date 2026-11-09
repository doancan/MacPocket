import XCTest
@testable import MacPocketCore

final class WeatherHourDetailTests: XCTestCase {
    private func hour(_ json: String, _ source: WeatherSource, extra: String? = nil) throws -> WeatherHour {
        let snapshot = try WeatherProviderClient.decode([Data(json.utf8)] + (extra.map { [Data($0.utf8)] } ?? []),
            source: source, location: .init(name: "İstanbul", latitude: 41, longitude: 29))
        return try XCTUnwrap(snapshot.hourly.first)
    }

    func testOpenMeteoPreservesZeroAndPrecedingHourTotals() throws {
        let h = try hour(#"{"current":{"temperature_2m":12},"hourly":{"time":["2026-11-09T12:00"],"temperature_2m":[12],"apparent_temperature":[10],"relative_humidity_2m":[75],"wind_speed_10m":[5],"wind_gusts_10m":[8],"wind_direction_10m":[270],"surface_pressure":[1012],"cloud_cover":[0],"precipitation_probability":[0],"precipitation":[0],"visibility":[12000],"uv_index":[2],"dew_point_2m":[8]}}"#, .openMeteo)
        XCTAssertEqual(h.apparent, 10); XCTAssertEqual(h.humidity, 75)
        XCTAssertEqual(h.windSpeed, 5); XCTAssertEqual(h.windGust, 8); XCTAssertEqual(h.windDirection, 270)
        XCTAssertEqual(h.pressure, 1012); XCTAssertEqual(h.cloudCover, 0)
        XCTAssertEqual(h.precipitationProbability, 0); XCTAssertEqual(h.precipitation, 0)
        XCTAssertEqual(h.precipitationHours, 1); XCTAssertEqual(h.precipitationTiming, .preceding)
        XCTAssertEqual(h.visibility, 12000); XCTAssertEqual(h.uvIndex, 2); XCTAssertEqual(h.dewPoint, 8)
        XCTAssertEqual(h.detailCount, 12)
    }

    func testVisualCrossingConvertsMetricWindAndVisibility() throws {
        let h = try hour(#"{"currentConditions":{"temp":12},"days":[{"datetimeEpoch":1794171600,"hours":[{"datetimeEpoch":1794200000,"temp":12,"feelslike":10,"humidity":70,"windspeed":18,"windgust":36,"winddir":90,"pressure":1010,"cloudcover":40,"precipprob":65,"precip":1.2,"visibility":8,"uvindex":3,"dew":7}]}]}"#, .visualCrossing)
        XCTAssertEqual(h.windSpeed, 5); XCTAssertEqual(h.windGust, 10); XCTAssertEqual(h.visibility, 8000)
        XCTAssertEqual(h.precipitationProbability, 65); XCTAssertEqual(h.precipitation, 1.2)
        XCTAssertEqual(h.precipitationHours, 1); XCTAssertNil(h.precipitationTiming)
        XCTAssertEqual(h.apparent, 10); XCTAssertEqual(h.humidity, 70); XCTAssertEqual(h.dewPoint, 7)
    }

    func testMETKeepsFollowingSixHourPeriodAndClearSkyUVSeparate() throws {
        let h = try hour(#"{"properties":{"timeseries":[{"time":"2026-11-09T12:00:00Z","data":{"instant":{"details":{"air_temperature":12,"relative_humidity":70,"wind_speed":5,"wind_speed_of_gust":9,"wind_from_direction":180,"air_pressure_at_sea_level":1010,"cloud_area_fraction":20,"ultraviolet_index_clear_sky":4,"dew_point_temperature":7}},"next_6_hours":{"summary":{"symbol_code":"rain"},"details":{"precipitation_amount":6,"probability_of_precipitation":80}}}}]}}"#, .metNorway)
        XCTAssertEqual(h.precipitation, 6); XCTAssertEqual(h.precipitationHours, 6); XCTAssertEqual(h.precipitationTiming, .following)
        XCTAssertEqual(h.precipitationProbability, 80); XCTAssertEqual(h.clearSkyUVIndex, 4); XCTAssertNil(h.uvIndex)
        XCTAssertEqual(h.windSpeed, 5); XCTAssertEqual(h.windGust, 9); XCTAssertNil(h.apparent)
    }

    func testWeatherAPIDoesNotCombineRainAndSnowProbabilities() throws {
        let h = try hour(#"{"current":{"temp_c":12},"forecast":{"forecastday":[{"date":"2026-11-09","hour":[{"time_epoch":1794200000,"temp_c":12,"feelslike_c":10,"humidity":70,"wind_kph":18,"gust_kph":36,"wind_degree":90,"pressure_mb":1010,"cloud":50,"chance_of_rain":60,"chance_of_snow":30,"precip_mm":2,"vis_km":8,"uv":3,"dewpoint_c":7}]}]}}"#, .weatherAPI)
        XCTAssertNil(h.precipitationProbability); XCTAssertEqual(h.rainProbability, 60); XCTAssertEqual(h.snowProbability, 30)
        XCTAssertEqual(h.windSpeed, 5); XCTAssertEqual(h.windGust, 10); XCTAssertEqual(h.visibility, 8000)
        XCTAssertEqual(h.precipitation, 2); XCTAssertEqual(h.precipitationHours, 1); XCTAssertEqual(h.uvIndex, 3)
    }

    func testPirateProbabilityFractionsAndIntensityRemainDistinctFromAmounts() throws {
        let h = try hour(#"{"currently":{"temperature":12},"hourly":{"data":[{"time":1794200000,"temperature":12,"apparentTemperature":10,"humidity":0.7,"cloudCover":0.4,"windSpeed":5,"windGust":10,"windBearing":90,"pressure":1010,"precipProbability":0.65,"precipIntensity":1.2,"visibility":8,"uvIndex":3,"dewPoint":7}]}}"#, .pirateWeather)
        XCTAssertEqual(h.humidity, 70); XCTAssertEqual(h.cloudCover, 40); XCTAssertEqual(h.precipitationProbability, 65)
        XCTAssertEqual(h.precipitationIntensity, 1.2); XCTAssertNil(h.precipitation); XCTAssertNil(h.precipitationHours)
        XCTAssertEqual(h.windSpeed, 5); XCTAssertEqual(h.visibility, 8000)
    }

    func testOpenWeatherThreeHourRainAndSnowAmountsAreNotHourlyRates() throws {
        let current = #"{"main":{"temp":12}}"#
        let h = try hour(current, .openWeather, extra: #"{"list":[{"dt":1794200000,"main":{"temp":12,"feels_like":10,"humidity":70,"pressure":1010},"wind":{"speed":5,"gust":10,"deg":90},"clouds":{"all":40},"pop":0.65,"rain":{"3h":2},"snow":{"3h":1},"visibility":8000}]}"#)
        XCTAssertEqual(h.precipitation, 3); XCTAssertEqual(h.precipitationHours, 3); XCTAssertEqual(h.precipitationTiming, .preceding)
        XCTAssertEqual(h.precipitationProbability, 65); XCTAssertNil(h.precipitationIntensity); XCTAssertEqual(h.visibility, 8000)
        let missing = try hour(current, .openWeather, extra: #"{"list":[{"dt":1794200000,"main":{"temp":12}}]}"#)
        XCTAssertNil(missing.precipitation); XCTAssertNil(missing.precipitationHours)
        XCTAssertEqual(missing.detailCount, 0)
    }

    func testTomorrowKeepsRainIntensityAndMetricVisibility() throws {
        let h = try hour(#"{"timelines":{"hourly":[{"time":"2026-11-09T12:00:00Z","values":{"temperature":12,"temperatureApparent":10,"humidity":70,"windSpeed":5,"windGust":10,"windDirection":90,"pressureSurfaceLevel":1010,"cloudCover":40,"precipitationProbability":65,"rainIntensity":1.2,"visibility":8,"uvIndex":3,"dewPoint":7}}]}}"#, .tomorrow)
        XCTAssertEqual(h.precipitationIntensity, 1.2); XCTAssertEqual(h.intensityIsRainOnly, true)
        XCTAssertEqual(h.precipitationProbability, 65); XCTAssertNil(h.precipitation)
        XCTAssertEqual(h.visibility, 8000); XCTAssertEqual(h.windSpeed, 5); XCTAssertEqual(h.apparent, 10)
    }

    func testInvalidOptionalDetailsAreOmittedAndMissingDoesNotMeanZero() throws {
        let h = try hour(#"{"current":{"temperature_2m":12},"hourly":{"time":["2026-11-09T12:00"],"temperature_2m":[12],"apparent_temperature":[999],"relative_humidity_2m":[true],"wind_speed_10m":[-1],"wind_direction_10m":[361],"surface_pressure":[9999],"cloud_cover":[101],"precipitation_probability":[-1],"precipitation":[null],"visibility":[-1],"uv_index":[-1]}}"#, .openMeteo)
        XCTAssertEqual(h.detailCount, 0); XCTAssertNil(h.precipitationHours)
        let legacy = try JSONDecoder().decode(WeatherHour.self, from: Data(#"{"time":1794200000,"temperature":12,"humidity":70,"wind-speed":5}"#.utf8))
        XCTAssertEqual(legacy.humidity, 70); XCTAssertEqual(legacy.windSpeed, 5); XCTAssertNil(legacy.precipitation)
    }
}
