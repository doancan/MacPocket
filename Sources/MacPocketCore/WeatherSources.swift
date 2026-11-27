import Foundation

public enum WeatherSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case visualCrossing, metNorway, openMeteo, ecmwf, ecmwfAI, gfs, icon
    case weatherAPI, pirateWeather, openWeather, tomorrow
    public var id: String { rawValue }
    public static var catalog: [Self] { allCases }
    public var localizedTitle: String {
        switch self {
        case .visualCrossing: "Visual Crossing"
        case .metNorway: "MET Norway"
        case .openMeteo: String(localized: "Open-Meteo · Otomatik")
        case .ecmwf: "Open-Meteo · ECMWF IFS"
        case .ecmwfAI: "Open-Meteo · ECMWF AIFS"
        case .gfs: "Open-Meteo · GFS"
        case .icon: "Open-Meteo · ICON"
        case .weatherAPI: "WeatherAPI.com"
        case .pirateWeather: "Pirate Weather"
        case .openWeather: String(localized: "OpenWeather · Ücretsiz API")
        case .tomorrow: "Tomorrow.io"
        }
    }
    public var requiresAPIKey: Bool { [.weatherAPI, .pirateWeather, .openWeather, .tomorrow].contains(self) }
    public var isOpenMeteo: Bool { [.openMeteo, .ecmwf, .ecmwfAI, .gfs, .icon].contains(self) }
    public var model: String? {
        switch self { case .ecmwf: "ecmwf_ifs025"; case .ecmwfAI: "ecmwf_aifs025_single"; case .gfs: "gfs_seamless"; case .icon: "icon_global"; default: nil }
    }
    public var refreshInterval: TimeInterval { self == .metNorway ? 10_800 : 3_600 }
    public var freeTierDescription: String {
        switch self {
        case .visualCrossing: String(localized: "Anahtarsız · Adil kullanım; sabit kota garantisi yok")
        case .metNorway: String(localized: "Anahtarsız · En az 3 saatte bir yenileme")
        case .openMeteo, .ecmwf, .ecmwfAI, .gfs, .icon: String(localized: "Anahtarsız · Ticari olmayan kullanım · 10.000 çağrı/gün")
        case .weatherAPI: String(localized: "Kendi API anahtarın · 100.000 çağrı/ay · 3 günlük tahmin")
        case .pirateWeather: String(localized: "Kendi API anahtarın · 10.000 çağrı/ay")
        case .openWeather: String(localized: "Kendi API anahtarın · Ücretsiz mevcut hava ve 5 günlük tahmin")
        case .tomorrow: String(localized: "Kendi API anahtarın · 500 çağrı/gün; 25 çağrı/saat")
        }
    }
    public var informationURL: URL {
        let address: String
        switch self {
        case .visualCrossing: address = "https://www.visualcrossing.com/resources/documentation/weather-api/free-weather-api-no-key/"
        case .metNorway: address = "https://api.met.no/doc/TermsOfService"
        case .openMeteo, .ecmwf, .ecmwfAI, .gfs, .icon: address = "https://open-meteo.com/en/pricing"
        case .weatherAPI: address = "https://www.weatherapi.com/pricing"
        case .pirateWeather: address = "https://pirateweather.net/"
        case .openWeather: address = "https://openweathermap.org/price"
        case .tomorrow: address = "https://support.tomorrow.io/hc/en-us/articles/20273728362644-Free-API-Plan-Rate-Limits"
        }
        return URL(string: address)!
    }
}

public struct WeatherBasket: Codable, Equatable, Sendable {
    public private(set) var sources: Set<WeatherSource>
    public private(set) var active: WeatherSource
    public init(sources: Set<WeatherSource> = [.visualCrossing, .metNorway, .openMeteo], active: WeatherSource = .visualCrossing) {
        self.sources = sources
        self.active = active
        self.sources.insert(active)
    }
    public var orderedSources: [WeatherSource] { WeatherSource.allCases.filter(sources.contains) }
    public mutating func select(_ source: WeatherSource) { sources.insert(source); active = source }
    public mutating func include(_ source: WeatherSource, included: Bool) {
        if included { sources.insert(source) }
        else if sources.count > 1 {
            sources.remove(source)
            if active == source, let next = orderedSources.first { active = next }
        }
    }
    public static func restored(_ data: Data?) -> Self {
        if let data, let saved = try? JSONDecoder().decode(Self.self, from: data) {
            return Self(sources: saved.sources, active: saved.active)
        }
        return Self()
    }
}

public enum WeatherSourceError: Error, LocalizedError, Equatable {
    case missingAPIKey, invalidAPIKey, authentication, rateLimited, invalidResponse, unavailable
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: String(localized: "Bu kaynak için kendi ücretsiz API anahtarını kaydet.")
        case .invalidAPIKey: String(localized: "API anahtarını kontrol et. Yalnız harf, rakam, nokta, tire ve alt çizgi kullanılabilir.")
        case .authentication: String(localized: "Kaynak erişimi reddetti. API anahtarını ve ücretsiz hesabının etkinliğini kontrol et.")
        case .rateLimited: String(localized: "Kaynağın istek sınırına ulaşıldı. Son veriler korunuyor; daha sonra yeniden dene.")
        case .invalidResponse: String(localized: "Seçili kaynaktan geçerli hava durumu alınamadı. Son veriler korunuyor.")
        case .unavailable: String(localized: "Seçili hava durumu kaynağına ulaşılamadı. Daha sonra yeniden dene veya başka kaynak seç.")
        }
    }
    public static func validatedKey(_ key: String?) throws -> String {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Self.missingAPIKey }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 512, value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }) else { throw Self.invalidAPIKey }
        return value
    }
}
