import Foundation

/// Adapters use only public forecast endpoints. Paid One Call/nowcast products are never requested.
public enum WeatherProviderClient {
    public static func requests(source: WeatherSource, location: WeatherLocation, language: String, apiKey: String? = nil) throws -> [URLRequest] {
        guard location.isValid else { throw WeatherError.invalidLocation }
        if source == .istatLegacy { return [try WeatherClient.request(location: location, language: language)] }
        let key = source.requiresAPIKey ? try WeatherSourceError.validatedKey(apiKey) : ""
        let lat = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), location.latitude)
        let lon = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), location.longitude)
        func request(_ address: String, _ parameters: [(String, String)]) -> URLRequest {
            var components = URLComponents(string: address)!
            components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("MacPocket/0.4.0 (https://github.com/doancan/MacPocket)", forHTTPHeaderField: "User-Agent")
            return request
        }
        if source.isOpenMeteo {
            var parameters = [("latitude", lat), ("longitude", lon), ("timezone", location.timeZone), ("forecast_days", "7"), ("wind_speed_unit", "ms"),
                ("current", "temperature_2m,apparent_temperature,relative_humidity_2m,surface_pressure,wind_speed_10m,weather_code,is_day"),
                ("hourly", "temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m,wind_gusts_10m,surface_pressure,cloud_cover,visibility,uv_index,weather_code,is_day"),
                ("daily", "temperature_2m_min,temperature_2m_max,weather_code")]
            if let model = source.model { parameters.append(("models", model)) }
            return [request("https://api.open-meteo.com/v1/forecast", parameters)]
        }
        switch source {
        case .visualCrossing:
            return [request("https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/\(lat),\(lon)/today/next4days",
                [("unitGroup", "metric"), ("include", "current,days,hours"), ("lang", language),
                 ("elements", "datetime,datetimeEpoch,temp,tempmin,tempmax,feelslike,humidity,pressure,windspeed,windgust,winddir,precip,precipprob,cloudcover,visibility,uvindex,dew,conditions,icon")])]
        case .metNorway:
            return [request("https://api.met.no/weatherapi/locationforecast/2.0/compact", [("lat", lat), ("lon", lon)])]
        case .weatherAPI:
            return [request("https://api.weatherapi.com/v1/forecast.json", [("key", key), ("q", "\(lat),\(lon)"), ("days", "3"), ("lang", language), ("aqi", "no"), ("alerts", "no")])]
        case .pirateWeather:
            return [request("https://api.pirateweather.net/forecast/\(key)/\(lat),\(lon)", [("units", "si"), ("lang", language), ("exclude", "minutely,alerts")])]
        case .openWeather:
            let parameters = [("appid", key), ("lat", lat), ("lon", lon), ("units", "metric"), ("lang", language)]
            return [request("https://api.openweathermap.org/data/2.5/weather", parameters), request("https://api.openweathermap.org/data/2.5/forecast", parameters)]
        case .tomorrow:
            return [request("https://api.tomorrow.io/v4/weather/forecast", [("apikey", key), ("location", "\(lat),\(lon)"), ("units", "metric")])]
        default: throw WeatherSourceError.invalidResponse
        }
    }

    public static func fetch(source: WeatherSource, location: WeatherLocation, language: String, apiKey: String? = nil,
                             session: URLSession = .shared, at date: Date = Date()) async throws -> WeatherSnapshot {
        if source == .istatLegacy {
            var result = try await WeatherClient.fetch(location: location, language: language, session: session)
            result.source = source; result.nextRefreshAt = date.addingTimeInterval(source.refreshInterval); return result
        }
        let requests = try requests(source: source, location: location, language: language, apiKey: apiKey)
        var bodies: [Data] = [], nextRefresh = date.addingTimeInterval(source.refreshInterval)
        for request in requests {
            try Task.checkCancellation()
            let data: Data, response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch is CancellationError { throw CancellationError() }
            catch { if Task.isCancelled { throw CancellationError() }; throw WeatherSourceError.unavailable }
            guard let http = response as? HTTPURLResponse else { throw WeatherSourceError.invalidResponse }
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw WeatherSourceError.authentication
            case 429: throw WeatherSourceError.rateLimited
            default: throw WeatherSourceError.unavailable
            }
            guard data.count <= 5_000_000 else { throw WeatherSourceError.invalidResponse }
            if let value = http.value(forHTTPHeaderField: "Expires") {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let expires = formatter.date(from: value) { nextRefresh = max(nextRefresh, min(expires, date.addingTimeInterval(86_400))) }
            }
            bodies.append(data)
        }
        try Task.checkCancellation()
        var result = try decode(bodies, source: source, location: location, at: date)
        result.nextRefreshAt = nextRefresh
        return result
    }

    public static func decode(_ bodies: [Data], source: WeatherSource, location: WeatherLocation, at date: Date = Date()) throws -> WeatherSnapshot {
        guard location.isValid else { throw WeatherError.invalidLocation }
        guard let data = bodies.first, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw WeatherSourceError.invalidResponse }
        let decoder = WeatherProviderDecoder(source: source, location: location, now: date)
        return try decoder.decode(root, extra: bodies.dropFirst().first)
    }
}

private struct WeatherProviderDecoder {
    let source: WeatherSource, location: WeatherLocation, now: Date
    typealias Object = [String: Any]
    private func object(_ value: Any?) -> Object { value as? Object ?? [:] }
    private func objects(_ value: Any?) -> [Object] { value as? [Object] ?? [] }
    private func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private func instant(_ value: Any?) -> Double? {
        if let value = number(value) { return (946_684_800...4_102_444_800).contains(value) ? value : nil }
        guard let text = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date.timeIntervalSince1970 }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date.timeIntervalSince1970 }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: location.timeZone)
        for pattern in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        }
        return nil
    }
    private func calendar(_ zone: String? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone ?? location.timeZone) ?? .current; return calendar
    }
    private func day(_ start: Double, low: Double?, high: Double?, icon: WeatherIcon?, zone: String? = nil) -> WeatherDay {
        let end = calendar(zone).date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: start))?.timeIntervalSince1970
        return .init(start: start, end: end, low: low, high: high, icon: icon)
    }
    private func icon(_ token: String?, night: Bool = false) -> WeatherIcon? {
        guard let token, !token.isEmpty else { return nil }
        var value = token.lowercased()
        if value.hasPrefix("fair") { value = value.contains("night") ? "partlycloudy-night" : "partlycloudy" }
        if night && value.contains("clear") { value += "-night" }
        return .init(icon: value, name: nil)
    }
    private func wmo(_ value: Any?, night: Bool = false) -> WeatherIcon? {
        guard let code = number(value) else { return nil }
        let token: String
        switch Int(code) {
        case 0: token = "clear"
        case 1, 2: token = "partlycloudy"
        case 3: token = "cloudy"
        case 45, 48: token = "fog"
        case 51...67, 80...82: token = "rain"
        case 71...77, 85, 86: token = "snow"
        case 95...99: token = "thunderstorm"
        default: return nil
        }
        return icon(token, night: night)
    }
    private func description(_ icon: WeatherIcon?) -> String? {
        icon?.localizedDescription
    }
    private func current(_ temperature: Double?, apparent: Double? = nil, humidity: Double? = nil, pressure: Double? = nil,
                         wind: Double? = nil, icon: WeatherIcon? = nil) -> WeatherConditions {
        .init(temperature: temperature, apparent: apparent, humidity: humidity, pressure: pressure, windSpeed: wind, conditions: description(icon), icon: icon)
    }
    private func detailed(_ hour: WeatherHour, apparent: Double? = nil, humidity: Double? = nil, wind: Double? = nil,
                          gust: Double? = nil, direction: Double? = nil, pressure: Double? = nil, cloud: Double? = nil,
                          probability: Double? = nil, rainProbability: Double? = nil, snowProbability: Double? = nil,
                          precipitation: Double? = nil, hours: Int? = nil, timing: WeatherPrecipitationTiming? = nil,
                          intensity: Double? = nil, rainOnly: Bool? = nil, visibility: Double? = nil,
                          uv: Double? = nil, clearSkyUV: Double? = nil, dew: Double? = nil) -> WeatherHour {
        func valid(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
            value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
        }
        var result = hour
        result.apparent = valid(apparent, -150...100); result.humidity = valid(humidity, 0...100)
        result.windSpeed = valid(wind, 0...200); result.windGust = valid(gust, 0...250)
        result.windDirection = valid(direction, 0...360); result.pressure = valid(pressure, 100...1_200)
        result.cloudCover = valid(cloud, 0...100); result.precipitationProbability = valid(probability, 0...100)
        result.rainProbability = valid(rainProbability, 0...100); result.snowProbability = valid(snowProbability, 0...100)
        result.precipitation = valid(precipitation, 0...5_000)
        if result.precipitation != nil { result.precipitationHours = hours; result.precipitationTiming = timing }
        result.precipitationIntensity = valid(intensity, 0...5_000); result.intensityIsRainOnly = rainOnly
        result.visibility = valid(visibility, 0...1_000_000); result.uvIndex = valid(uv, 0...50)
        result.clearSkyUVIndex = valid(clearSkyUV, 0...50); result.dewPoint = valid(dew, -150...100)
        return result
    }
    private func aggregate(_ hours: [WeatherHour]) -> [WeatherDay] {
        let calendar = calendar()
        return Dictionary(grouping: hours, by: { calendar.startOfDay(for: Date(timeIntervalSince1970: $0.time)).timeIntervalSince1970 })
            .sorted { $0.key < $1.key }.map { start, values in
                let temperatures = values.compactMap(\.temperature)
                return day(start, low: temperatures.min(), high: temperatures.max(), icon: values[values.count / 2].icon)
            }
    }
    func decode(_ root: Object, extra: Data?) throws -> WeatherSnapshot {
        var current: WeatherConditions, hours: [WeatherHour] = [], days: [WeatherDay] = [], zone = location.timeZone
        var attribution: [String] = []
        switch source {
        case .openMeteo, .ecmwf, .ecmwfAI, .gfs, .icon:
            zone = root["timezone"] as? String ?? zone
            let c = object(root["current"]), h = object(root["hourly"]), d = object(root["daily"])
            current = self.current(number(c["temperature_2m"]), apparent: number(c["apparent_temperature"]), humidity: number(c["relative_humidity_2m"]),
                pressure: number(c["surface_pressure"]), wind: number(c["wind_speed_10m"]), icon: wmo(c["weather_code"], night: number(c["is_day"]) == 0))
            func item(_ object: Object, _ field: String, _ index: Int) -> Any? {
                guard let values = object[field] as? [Any], values.indices.contains(index) else { return nil }; return values[index]
            }
            for (i, time) in (h["time"] as? [Any] ?? []).enumerated() {
                guard let time = instant(time) else { continue }
                hours.append(detailed(.init(night: number(item(h, "is_day", i)) == 0 ? 1 : 0, time: time, temperature: number(item(h, "temperature_2m", i)), icon: wmo(item(h, "weather_code", i))),
                    apparent: number(item(h, "apparent_temperature", i)), humidity: number(item(h, "relative_humidity_2m", i)),
                    wind: number(item(h, "wind_speed_10m", i)), gust: number(item(h, "wind_gusts_10m", i)), direction: number(item(h, "wind_direction_10m", i)),
                    pressure: number(item(h, "surface_pressure", i)), cloud: number(item(h, "cloud_cover", i)),
                    probability: number(item(h, "precipitation_probability", i)), precipitation: number(item(h, "precipitation", i)), hours: 1, timing: .preceding,
                    visibility: number(item(h, "visibility", i)), uv: number(item(h, "uv_index", i)), dew: number(item(h, "dew_point_2m", i))))
            }
            for (i, time) in (d["time"] as? [Any] ?? []).enumerated() {
                guard let time = instant(time) else { continue }
                days.append(day(time, low: number(item(d, "temperature_2m_min", i)), high: number(item(d, "temperature_2m_max", i)), icon: wmo(item(d, "weather_code", i)), zone: zone))
            }
            attribution = ["https://open-meteo.com/"]
            if [.openMeteo, .ecmwf, .ecmwfAI].contains(source) { attribution.append("https://www.ecmwf.int/") }
            if [.openMeteo, .gfs].contains(source) { attribution.append("https://www.noaa.gov/") }
            if [.openMeteo, .icon].contains(source) { attribution.append("https://www.dwd.de/") }
        case .visualCrossing:
            zone = root["timezone"] as? String ?? zone
            let c = object(root["currentConditions"])
            current = self.current(number(c["temp"]), apparent: number(c["feelslike"]), humidity: number(c["humidity"]), pressure: number(c["pressure"]),
                wind: number(c["windspeed"]).map { $0 / 3.6 }, icon: icon(c["icon"] as? String))
            for d in objects(root["days"]) {
                guard let time = instant(d["datetimeEpoch"] ?? d["datetime"]) else { continue }
                days.append(day(time, low: number(d["tempmin"]), high: number(d["tempmax"]), icon: icon(d["icon"] as? String), zone: zone))
                for h in objects(d["hours"]) {
                    guard let time = instant(h["datetimeEpoch"]) else { continue }
                    let token = h["icon"] as? String
                    hours.append(detailed(.init(night: token?.contains("night") == true ? 1 : 0, time: time, temperature: number(h["temp"]), icon: icon(token)),
                        apparent: number(h["feelslike"]), humidity: number(h["humidity"]), wind: number(h["windspeed"]).map { $0 / 3.6 },
                        gust: number(h["windgust"]).map { $0 / 3.6 }, direction: number(h["winddir"]), pressure: number(h["pressure"]), cloud: number(h["cloudcover"]),
                        probability: number(h["precipprob"]), precipitation: number(h["precip"]), hours: 1,
                        visibility: number(h["visibility"]).map { $0 * 1_000 }, uv: number(h["uvindex"]), dew: number(h["dew"])))
                }
            }
            attribution = ["https://www.visualcrossing.com/"]
        case .metNorway:
            let series = objects(object(root["properties"])["timeseries"])
            let valid = series.compactMap { value -> (Double, Object)? in instant(value["time"]).map { ($0, object(value["data"])) } }
            guard let nearest = valid.filter({ $0.0 <= now.timeIntervalSince1970 }).last ?? valid.first else { throw WeatherSourceError.invalidResponse }
            func symbol(_ data: Object) -> WeatherIcon? {
                icon(object(object(data["next_1_hours"] ?? data["next_6_hours"] ?? data["next_12_hours"])["summary"])["symbol_code"] as? String)
            }
            let c = object(object(nearest.1["instant"])["details"])
            current = self.current(number(c["air_temperature"]), humidity: number(c["relative_humidity"]), pressure: number(c["air_pressure_at_sea_level"]), wind: number(c["wind_speed"]), icon: symbol(nearest.1))
            hours = valid.map { time, data in
                let token = symbol(data)
                let c = object(object(data["instant"])["details"])
                let period = [("next_1_hours", 1), ("next_6_hours", 6), ("next_12_hours", 12)].first { data[$0.0] != nil }
                let p = object(object(period.flatMap { data[$0.0] })["details"])
                return detailed(.init(night: token?.icon?.contains("night") == true ? 1 : 0, time: time, temperature: number(c["air_temperature"]), icon: token),
                    humidity: number(c["relative_humidity"]), wind: number(c["wind_speed"]), gust: number(c["wind_speed_of_gust"]),
                    direction: number(c["wind_from_direction"]), pressure: number(c["air_pressure_at_sea_level"]), cloud: number(c["cloud_area_fraction"]),
                    probability: number(p["probability_of_precipitation"]), precipitation: number(p["precipitation_amount"]), hours: period?.1, timing: .following,
                    clearSkyUV: number(c["ultraviolet_index_clear_sky"]), dew: number(c["dew_point_temperature"]))
            }
            days = aggregate(hours); attribution = ["https://www.met.no/"]
        case .weatherAPI:
            zone = object(root["location"])["tz_id"] as? String ?? zone
            let c = object(root["current"])
            func symbol(_ c: Object) -> WeatherIcon? {
                guard let code = number(object(c["condition"])["code"]) else { return nil }
                let token: String
                switch Int(code) {
                case 1000: token = "clear"
                case 1003: token = "partlycloudy"
                case 1006, 1009: token = "cloudy"
                case 1030, 1135, 1147: token = "fog"
                case 1087, 1273, 1276, 1279, 1282: token = "thunderstorm"
                case 1066, 1114, 1117, 1210...1225, 1255, 1258: token = "snow"
                case 1069, 1204, 1207, 1249, 1252: token = "sleet"
                case 1063, 1072, 1150...1201, 1240...1246: token = "rain"
                case 1237, 1261, 1264: token = "sleet"
                default: return nil
                }
                return icon(token, night: number(c["is_day"]) == 0)
            }
            current = self.current(number(c["temp_c"]), apparent: number(c["feelslike_c"]), humidity: number(c["humidity"]), pressure: number(c["pressure_mb"]), wind: number(c["wind_kph"]).map { $0 / 3.6 }, icon: symbol(c))
            for d in objects(object(root["forecast"])["forecastday"]) {
                guard let time = instant(d["date_epoch"] ?? d["date"]) else { continue }
                let values = object(d["day"])
                days.append(day(time, low: number(values["mintemp_c"]), high: number(values["maxtemp_c"]), icon: symbol(values), zone: zone))
                for h in objects(d["hour"]) {
                    guard let time = instant(h["time_epoch"]) else { continue }
                    hours.append(detailed(.init(night: number(h["is_day"]) == 0 ? 1 : 0, time: time, temperature: number(h["temp_c"]), icon: symbol(h)),
                        apparent: number(h["feelslike_c"]), humidity: number(h["humidity"]), wind: number(h["wind_kph"]).map { $0 / 3.6 },
                        gust: number(h["gust_kph"]).map { $0 / 3.6 }, direction: number(h["wind_degree"]), pressure: number(h["pressure_mb"]), cloud: number(h["cloud"]),
                        rainProbability: number(h["chance_of_rain"]), snowProbability: number(h["chance_of_snow"]), precipitation: number(h["precip_mm"]), hours: 1,
                        visibility: number(h["vis_km"]).map { $0 * 1_000 }, uv: number(h["uv"]), dew: number(h["dewpoint_c"])))
                }
            }
            attribution = ["https://www.weatherapi.com/"]
        case .pirateWeather:
            zone = root["timezone"] as? String ?? zone
            let c = object(root["currently"])
            current = self.current(number(c["temperature"]), apparent: number(c["apparentTemperature"]), humidity: number(c["humidity"]).map { $0 * 100 }, pressure: number(c["pressure"]), wind: number(c["windSpeed"]), icon: icon(c["icon"] as? String))
            hours = objects(object(root["hourly"])["data"]).compactMap { h in
                guard let time = instant(h["time"]) else { return nil }
                let token = h["icon"] as? String
                return detailed(.init(night: token?.contains("night") == true ? 1 : 0, time: time, temperature: number(h["temperature"]), icon: icon(token)),
                    apparent: number(h["apparentTemperature"]), humidity: number(h["humidity"]).map { $0 * 100 }, wind: number(h["windSpeed"]),
                    gust: number(h["windGust"]), direction: number(h["windBearing"]), pressure: number(h["pressure"]), cloud: number(h["cloudCover"]).map { $0 * 100 },
                    probability: number(h["precipProbability"]).map { $0 * 100 }, intensity: number(h["precipIntensity"]),
                    visibility: number(h["visibility"]).map { $0 * 1_000 }, uv: number(h["uvIndex"]), dew: number(h["dewPoint"]))
            }
            days = objects(object(root["daily"])["data"]).compactMap { d in
                guard let time = instant(d["time"]) else { return nil }
                return day(time, low: number(d["temperatureLow"] ?? d["temperatureMin"]), high: number(d["temperatureHigh"] ?? d["temperatureMax"]), icon: icon(d["icon"] as? String), zone: zone)
            }
            attribution = ["https://pirateweather.net/"]
        case .openWeather:
            let c = object(root["main"])
            func symbol(_ data: Object) -> WeatherIcon? {
                guard let condition = objects(data["weather"]).first else { return nil }
                let value = condition["main"] as? String
                let night = (condition["icon"] as? String)?.hasSuffix("n") == true
                return icon(value, night: night)
            }
            current = self.current(number(c["temp"]), apparent: number(c["feels_like"]), humidity: number(c["humidity"]), pressure: number(c["pressure"]), wind: number(object(root["wind"])["speed"]), icon: symbol(root))
            guard let extra, let forecast = (try? JSONSerialization.jsonObject(with: extra)) as? Object else { throw WeatherSourceError.invalidResponse }
            hours = objects(forecast["list"]).compactMap { h in
                guard let time = instant(h["dt"]) else { return nil }
                let c = object(h["main"]), wind = object(h["wind"])
                let rain = number(object(h["rain"])["3h"]), snow = number(object(h["snow"])["3h"])
                let amount: Double? = rain == nil && snow == nil ? nil : (rain ?? 0) + (snow ?? 0)
                return detailed(.init(night: (objects(h["weather"]).first?["icon"] as? String)?.hasSuffix("n") == true ? 1 : 0,
                             time: time, temperature: number(c["temp"]), icon: symbol(h)),
                    apparent: number(c["feels_like"]), humidity: number(c["humidity"]), wind: number(wind["speed"]), gust: number(wind["gust"]), direction: number(wind["deg"]),
                    pressure: number(c["pressure"]), cloud: number(object(h["clouds"])["all"]), probability: number(h["pop"]).map { $0 * 100 },
                    precipitation: amount, hours: 3, timing: .preceding, visibility: number(h["visibility"]))
            }
            days = aggregate(hours); attribution = ["https://openweathermap.org/"]
        case .tomorrow:
            let series = object(root["timelines"]), values = objects(series["hourly"])
            guard let nearest = values.last(where: { (instant($0["time"]) ?? .infinity) <= now.timeIntervalSince1970 }) ?? values.first else { throw WeatherSourceError.invalidResponse }
            func symbol(_ values: Object, daily: Bool = false) -> WeatherIcon? {
                guard let code = number(values[daily ? "weatherCodeMax" : "weatherCode"]) else { return nil }
                let token: String
                switch Int(code) {
                case 1000: token = "clear"
                case 1100, 1101: token = "partlycloudy"
                case 1001, 1102: token = "cloudy"
                case 2000, 2100: token = "fog"
                case 5000...5101: token = "snow"
                case 6000...7102: token = "sleet"
                case 8000: token = "thunderstorm"
                case 4000...4201: token = "rain"
                default: return nil
                }
                return icon(token)
            }
            let c = object(nearest["values"])
            current = self.current(number(c["temperature"]), apparent: number(c["temperatureApparent"]), humidity: number(c["humidity"]), pressure: number(c["pressureSurfaceLevel"]), wind: number(c["windSpeed"]), icon: symbol(c))
            hours = values.compactMap { h in
                guard let time = instant(h["time"]) else { return nil }
                let values = object(h["values"])
                return detailed(.init(night: nil, time: time, temperature: number(values["temperature"]), icon: symbol(values)),
                    apparent: number(values["temperatureApparent"]), humidity: number(values["humidity"]), wind: number(values["windSpeed"]), gust: number(values["windGust"]),
                    direction: number(values["windDirection"]), pressure: number(values["pressureSurfaceLevel"]), cloud: number(values["cloudCover"]),
                    probability: number(values["precipitationProbability"]), intensity: number(values["rainIntensity"]), rainOnly: true,
                    visibility: number(values["visibility"]).map { $0 * 1_000 }, uv: number(values["uvIndex"]), dew: number(values["dewPoint"]))
            }
            days = objects(series["daily"]).compactMap { d in
                guard let time = instant(d["time"]) else { return nil }
                let c = object(d["values"])
                return day(time, low: number(c["temperatureMin"]), high: number(c["temperatureMax"]), icon: symbol(c, daily: true), zone: zone)
            }
            attribution = ["https://www.tomorrow.io/"]
        case .istatLegacy: throw WeatherSourceError.invalidResponse
        }
        guard let temperature = current.temperature, temperature.isFinite, (-150...100).contains(temperature) else { throw WeatherSourceError.invalidResponse }
        hours = hours.filter { $0.time.isFinite && $0.temperature.map { $0.isFinite && (-150...100).contains($0) } == true }.sorted { $0.time < $1.time }
        days = days.filter {
            guard let low = $0.low, let high = $0.high else { return false }
            return $0.start.isFinite && (-150...100).contains(low) && (-150...100).contains(high) && low <= high
        }.sorted { $0.start < $1.start }
        // Sparse model samples are not presented as full-day minima/maxima.
        if source == .metNorway || source == .openWeather {
            let today = calendar(zone).startOfDay(for: now).timeIntervalSince1970
            days.removeAll { $0.start <= today }
        }
        var result = WeatherSnapshot(location: location, current: current, hourly: hours, forecast: days,
            attributions: attribution.map { .init(link: $0) }, fetchedAt: now, serverTimeZone: zone)
        result.source = source
        return result
    }
}
