import Foundation

public struct WeatherLocation: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZone: String
    public var id: String { "\(latitude),\(longitude)" }
    public init(name: String, latitude: Double, longitude: Double, timeZone: String = "Europe/Istanbul") {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
    }
    /// MapKit addresses can repeat the place ("Ankara Ankara, Türkiye"); shown with the repeat dropped.
    public var displayName: String { Self.collapsingRepeatedPrefix(name) }

    static func collapsingRepeatedPrefix(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        func bare(_ word: String) -> String { word.trimmingCharacters(in: CharacterSet(charactersIn: ",")).lowercased() }
        for length in stride(from: words.count / 2, through: 1, by: -1) {
            let head = words[0..<length].map(bare), next = words[length..<(2 * length)].map(bare)
            if head == next { return words[length...].joined(separator: " ") }
        }
        return text
    }

    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

public struct WeatherConditions: Sendable {
    public let temperature: Double?
    public let apparent: Double?
    public let humidity: Double?
    public let pressure: Double?
    public let windSpeed: Double?
    public let conditions: String?
    public let icon: WeatherIcon?
}

public struct WeatherIcon: Sendable {
    public let icon: String?
    public let name: String?
    public var symbol: String { symbol(isNight: false) }
    public var localizedDescription: String? {
        guard let token = icon?.lowercased() else { return name }
        if token.contains("thunder") || token.contains("storm") { return String(localized: "Gök gürültülü") }
        if token.contains("snow") { return String(localized: "Karlı") }
        if token.contains("sleet") { return String(localized: "Karla karışık yağmurlu") }
        if token.contains("rain") || token.contains("drizzle") { return String(localized: "Yağmurlu") }
        if token.contains("fog") || token.contains("mist") { return String(localized: "Sisli") }
        if token.contains("partly") { return String(localized: "Parçalı bulutlu") }
        if token.contains("cloud") { return String(localized: "Bulutlu") }
        if token.contains("clear") || token.contains("sun") { return String(localized: "Weather.condition.clear", defaultValue: "Açık") }
        return name
    }
    public func symbol(isNight: Bool) -> String {
        let name = icon?.lowercased() ?? ""
        let night = isNight || name.contains("night")
        if name.contains("thunder") || name.contains("storm") { return "cloud.bolt.rain.fill" }
        if name.contains("snow") { return "cloud.snow.fill" }
        if name.contains("sleet") || name.contains("hail") { return "cloud.sleet.fill" }
        if name.contains("rain") || name.contains("drizzle") { return "cloud.rain.fill" }
        if name.contains("fog") || name.contains("mist") || name.contains("haze") { return "cloud.fog.fill" }
        if name.contains("partly") { return night ? "cloud.moon.fill" : "cloud.sun.fill" }
        if name.contains("cloud") || name.contains("overcast") { return "cloud.fill" }
        if name.contains("wind") { return "wind" }
        if name.contains("night") { return "moon.stars.fill" }
        if name.contains("clear") || name.contains("sun") { return night ? "moon.stars.fill" : "sun.max.fill" }
        return "cloud.sun.fill"
    }
}

public struct WeatherHour: Sendable, Identifiable {
    public let night: Int?
    public var symbol: String { icon?.symbol(isNight: night == 1) ?? "thermometer.medium" }
    public let time: Double
    public let temperature: Double?
    public let icon: WeatherIcon?
    // Temperatures are Celsius, wind m/s, pressure hPa, visibility metres, probabilities percent.
    // Precipitation amounts (mm) retain their provider interval; intensity is a separate mm/h rate.
    public var apparent: Double? = nil
    public var humidity: Double? = nil
    public var windSpeed: Double? = nil
    public var windGust: Double? = nil
    public var windDirection: Double? = nil
    public var pressure: Double? = nil
    public var cloudCover: Double? = nil
    public var precipitationProbability: Double? = nil
    public var rainProbability: Double? = nil
    public var snowProbability: Double? = nil
    public var precipitation: Double? = nil
    public var precipitationHours: Int? = nil
    public var precipitationTiming: WeatherPrecipitationTiming? = nil
    public var precipitationIntensity: Double? = nil
    public var intensityIsRainOnly: Bool? = nil
    public var visibility: Double? = nil
    public var uvIndex: Double? = nil
    public var clearSkyUVIndex: Double? = nil
    public var dewPoint: Double? = nil
    public var detailCount: Int {
        [apparent, humidity, windSpeed, windGust, windDirection, pressure, cloudCover, precipitationProbability,
         rainProbability, snowProbability, precipitation, precipitationIntensity, visibility, uvIndex, clearSkyUVIndex, dewPoint].compactMap { $0 }.count
    }
    public var id: Double { time }
}

public enum WeatherPrecipitationTiming: String, Sendable { case preceding, following }

public struct WeatherDay: Sendable, Identifiable {
    public let start: Double
    public let end: Double?
    public let low: Double?
    public let high: Double?
    public let icon: WeatherIcon?
    public var id: Double { start }
}

public struct WeatherAttribution: Sendable {
    public let link: String?
    public var url: URL? { link.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
    public var title: String {
        if let host = url?.host {
            let sources: [(String, String)] = [("open-meteo.com", "Open-Meteo"), ("visualcrossing.com", "Visual Crossing"),
                ("met.no", "MET Norway"), ("weatherapi.com", "WeatherAPI.com"), ("pirateweather.net", "Pirate Weather"),
                ("openweathermap.org", "OpenWeather"), ("tomorrow.io", "Tomorrow.io"), ("ecmwf.int", "ECMWF"),
                ("dwd.de", "DWD"), ("noaa.gov", "NOAA")]
            if let match = sources.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) }) { return match.1 }
        }
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
    public var source: WeatherSource? = nil
    public var nextRefreshAt: Date? = nil
    public var timeZone: TimeZone { TimeZone(identifier: serverTimeZone ?? location.timeZone) ?? .current }
    public var symbol: String { current.icon?.symbol ?? "thermometer.medium" }
}

public enum WeatherError: Error, LocalizedError, Equatable {
    case invalidLocation, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidLocation: String(localized: "Geçerli bir hava durumu konumu seç.")
        case .invalidResponse: String(localized: "Hava durumu yanıtı okunamadı. Son veriler korunuyor.")
        }
    }
}
