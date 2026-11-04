import Foundation

public struct WeatherLocation: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZone: String
    public var id: String { "\(latitude),\(longitude)" }
    public init(name: String, latitude: Double, longitude: Double, timeZone: String = "Europe/Istanbul") {
        self.name = name; self.latitude = latitude; self.longitude = longitude; self.timeZone = timeZone
    }
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

public struct WeatherConditions: Decodable, Sendable {
    public let temperature: Double?
    public let apparent: Double?
    public let humidity: Double?
    public let pressure: Double?
    public let windSpeed: Double?
    public let conditions: String?
    public let icon: WeatherIcon?
    enum CodingKeys: String, CodingKey {
        case temperature, apparent, humidity, pressure, conditions, icon
        case windSpeed = "wind-speed"
    }
}

public struct WeatherIcon: Decodable, Sendable {
    public let icon: String?
    public let name: String?
    public var symbol: String { symbol(isNight: false) }
    public func symbol(isNight: Bool) -> String {
        let name = icon?.lowercased() ?? ""
        if name.contains("thunder") || name.contains("storm") { return "cloud.bolt.rain.fill" }
        if name.contains("snow") { return "cloud.snow.fill" }
        if name.contains("sleet") || name.contains("hail") { return "cloud.sleet.fill" }
        if name.contains("rain") || name.contains("drizzle") { return "cloud.rain.fill" }
        if name.contains("fog") || name.contains("mist") || name.contains("haze") { return "cloud.fog.fill" }
        if name.contains("partly") { return isNight ? "cloud.moon.fill" : "cloud.sun.fill" }
        if name.contains("cloud") || name.contains("overcast") { return "cloud.fill" }
        if name.contains("wind") { return "wind" }
        if name.contains("night") { return "moon.stars.fill" }
        if name.contains("clear") || name.contains("sun") { return isNight ? "moon.stars.fill" : "sun.max.fill" }
        return "cloud.sun.fill"
    }
}

public struct WeatherHour: Decodable, Sendable, Identifiable {
    public let night: Int?
    public var symbol: String { icon?.symbol(isNight: night == 1) ?? "cloud.sun.fill" }
    public let time: Double
    public let temperature: Double?
    public let icon: WeatherIcon?
    public var id: Double { time }
}

public struct WeatherDay: Decodable, Sendable, Identifiable {
    public let start: Double
    public let end: Double?
    public let low: Double?
    public let high: Double?
    public let icon: WeatherIcon?
    public var id: Double { start }
    enum CodingKeys: String, CodingKey { case start, end, icon; case low = "temperature-low", high = "temperature-high" }
}

public struct WeatherAttribution: Decodable, Sendable {
    public let link: String?
    public var url: URL? { link.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
    public var title: String {
        if let host = url?.host, host == "apple.com" || host.hasSuffix(".apple.com") { return "Apple Weather" }
        return String(localized: "Veri kaynağı")
    }
}

public struct WeatherSnapshot: Sendable {
    public let location: WeatherLocation
    public let current: WeatherConditions
    public let hourly: [WeatherHour]
    public let forecast: [WeatherDay]
    public let attributions: [WeatherAttribution]
    public let fetchedAt: Date
    public let serverTimeZone: String?
    public var timeZone: TimeZone { TimeZone(identifier: serverTimeZone ?? location.timeZone) ?? .current }
    public var symbol: String { current.icon?.symbol ?? "cloud.sun.fill" }

    public static func decode(_ data: Data, location: WeatherLocation, at date: Date = Date()) throws -> Self {
        struct Response: Decodable {
            struct ErrorBody: Decodable { let code: String? }
            struct Weather: Decodable { let currently: WeatherConditions?; let hourly: [WeatherHour]?; let forecast: [WeatherDay]? }
            struct Metadata: Decodable {
                struct Provider: Decodable { let attribution: [WeatherAttribution]? }
                struct Place: Decodable { let timezone: String? }
                let provider: Provider?
                let location: Place?
            }
            let weather: Weather?
            let error: ErrorBody?
            let metadata: Metadata?
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw WeatherError.invalidResponse }
        if let error = response.error { throw WeatherError.server(error.code ?? "unknown") }
        guard let weather = response.weather, let current = weather.currently,
              let temperature = current.temperature, temperature.isFinite, (-150...100).contains(temperature) else {
            throw WeatherError.invalidResponse
        }
        return Self(location: location, current: current, hourly: weather.hourly ?? [], forecast: weather.forecast ?? [],
                    attributions: response.metadata?.provider?.attribution ?? [], fetchedAt: date,
                    serverTimeZone: response.metadata?.location?.timezone)
    }
}

public enum WeatherError: Error, LocalizedError, Equatable {
    case invalidLocation, invalidResponse, http(Int), server(String)
    public var errorDescription: String? {
        switch self {
        case .invalidLocation: String(localized: "Geçerli bir hava durumu konumu seç.")
        case .invalidResponse: String(localized: "Hava durumu yanıtı okunamadı. Son veriler korunuyor.")
        case .http: String(localized: "Hava durumu sunucusuna ulaşılamadı. Daha sonra yeniden dene.")
        case .server(let code):
            switch code {
            case "locationnotfound": String(localized: "Bu konum için hava durumu bulunamadı. Yakındaki bir şehir veya ilçe seç.")
            case "limited": String(localized: "Hava durumu istek sınırına ulaşıldı. Daha sonra yeniden dene.")
            case "notfound", "expired", "trialexpired": String(localized: "Hava durumu kimliği veya veri paketi şu anda kullanılamıyor.")
            default: String(localized: "Hava durumu alınamadı. Daha sonra yeniden dene.")
            }
        }
    }
}

public enum WeatherClient {
    public static func request(location: WeatherLocation, language: String, at date: Date = Date()) throws -> URLRequest {
        guard location.isValid else { throw WeatherError.invalidLocation }
        var request = URLRequest(url: WeatherAPIConfiguration.endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(WeatherAPIConfiguration.clientVersion, forHTTPHeaderField: "X-Client-App-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identifier": WeatherAPIConfiguration.deviceIdentifier, "provider": WeatherAPIConfiguration.provider,
            "setapp": WeatherAPIConfiguration.setapp, "language": language,
            "latitude": String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.latitude),
            "longitude": String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.longitude),
            "time": String(Int(date.timeIntervalSince1970)), "forced": false,
            "units": ["temperature": 0, "wind": 0, "precipitation": 0],
        ])
        return request
    }

    public static func fetch(location: WeatherLocation, language: String, session: URLSession = .shared) async throws -> WeatherSnapshot {
        let request = try request(location: location, language: language)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try WeatherSnapshot.decode(data, location: location)
    }
}
