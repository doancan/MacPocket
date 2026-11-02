import Foundation

public struct City: Identifiable, Hashable, Sendable {
    public let name: String
    public let coordinate: Coordinate
    public var id: String { name }

    public init(name: String, coordinate: Coordinate) {
        self.name = name
        self.coordinate = coordinate
    }
}

/// Embedded fallback list for the night schedule when location access is unavailable:
/// the 81 Turkish province centers (proper nouns, shown verbatim) and 40 large world cities.
public enum CityCatalog {
    private static func city(_ name: String, _ latitude: Double, _ longitude: Double) -> City {
        City(name: name, coordinate: Coordinate(latitude: latitude, longitude: longitude))
    }

    public static let all: [City] = turkishProvinces + worldCities

    /// The catalog city closest to `coordinate` (great-circle distance), or nil when none lies within
    /// `maxKilometers`. Offline: names a fetched location without reverse geocoding.
    public static func nearest(to coordinate: Coordinate, within maxKilometers: Double = .infinity) -> City? {
        guard let city = all.min(by: { distance(coordinate, $0.coordinate) < distance(coordinate, $1.coordinate) }),
              distance(coordinate, city.coordinate) <= maxKilometers else { return nil }
        return city
    }

    /// Haversine distance in kilometres.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6371 * asin(min(1, sqrt(h)))
    }

    public static let turkishProvinces: [City] = [
        city("Adana", 37.00, 35.32),
        city("Adıyaman", 37.76, 38.28),
        city("Afyonkarahisar", 38.76, 30.54),
        city("Ağrı", 39.72, 43.05),
        city("Amasya", 40.65, 35.83),
        city("Ankara", 39.93, 32.86),
        city("Antalya", 36.90, 30.70),
        city("Artvin", 41.18, 41.82),
        city("Aydın", 37.85, 27.85),
        city("Balıkesir", 39.65, 27.89),
        city("Bilecik", 40.14, 29.98),
        city("Bingöl", 38.88, 40.50),
        city("Bitlis", 38.40, 42.11),
        city("Bolu", 40.74, 31.61),
        city("Burdur", 37.72, 30.29),
        city("Bursa", 40.19, 29.06),
        city("Çanakkale", 40.15, 26.41),
        city("Çankırı", 40.60, 33.62),
        city("Çorum", 40.55, 34.95),
        city("Denizli", 37.78, 29.09),
        city("Diyarbakır", 37.91, 40.24),
        city("Edirne", 41.68, 26.56),
        city("Elazığ", 38.67, 39.22),
        city("Erzincan", 39.75, 39.49),
        city("Erzurum", 39.90, 41.27),
        city("Eskişehir", 39.78, 30.52),
        city("Gaziantep", 37.07, 37.38),
        city("Giresun", 40.91, 38.39),
        city("Gümüşhane", 40.46, 39.48),
        city("Hakkâri", 37.58, 43.74),
        city("Hatay", 36.40, 36.35),
        city("Isparta", 37.76, 30.55),
        city("Mersin", 36.81, 34.64),
        city("İstanbul", 41.01, 28.98),
        city("İzmir", 38.42, 27.14),
        city("Kars", 40.60, 43.10),
        city("Kastamonu", 41.38, 33.78),
        city("Kayseri", 38.73, 35.49),
        city("Kırklareli", 41.74, 27.22),
        city("Kırşehir", 39.15, 34.16),
        city("Kocaeli", 40.77, 29.94),
        city("Konya", 37.87, 32.48),
        city("Kütahya", 39.42, 29.98),
        city("Malatya", 38.35, 38.31),
        city("Manisa", 38.61, 27.43),
        city("Kahramanmaraş", 37.58, 36.94),
        city("Mardin", 37.31, 40.74),
        city("Muğla", 37.22, 28.36),
        city("Muş", 38.74, 41.51),
        city("Nevşehir", 38.62, 34.71),
        city("Niğde", 37.97, 34.68),
        city("Ordu", 40.98, 37.88),
        city("Rize", 41.02, 40.52),
        city("Sakarya", 40.69, 30.40),
        city("Samsun", 41.29, 36.33),
        city("Siirt", 37.93, 41.94),
        city("Sinop", 42.03, 35.15),
        city("Sivas", 39.75, 37.02),
        city("Tekirdağ", 40.98, 27.51),
        city("Tokat", 40.31, 36.55),
        city("Trabzon", 41.00, 39.72),
        city("Tunceli", 39.11, 39.55),
        city("Şanlıurfa", 37.16, 38.79),
        city("Uşak", 38.68, 29.41),
        city("Van", 38.49, 43.38),
        city("Yozgat", 39.82, 34.80),
        city("Zonguldak", 41.46, 31.80),
        city("Aksaray", 38.37, 34.03),
        city("Bayburt", 40.26, 40.23),
        city("Karaman", 37.18, 33.23),
        city("Kırıkkale", 39.85, 33.52),
        city("Batman", 37.88, 41.13),
        city("Şırnak", 37.52, 42.46),
        city("Bartın", 41.64, 32.34),
        city("Ardahan", 41.11, 42.70),
        city("Iğdır", 39.92, 44.05),
        city("Yalova", 40.65, 29.27),
        city("Karabük", 41.20, 32.62),
        city("Kilis", 36.72, 37.12),
        city("Osmaniye", 37.07, 36.25),
        city("Düzce", 40.84, 31.16),
    ]

    public static let worldCities: [City] = [
        city(String(localized: "Londra"), 51.51, -0.13),
        city(String(localized: "Paris"), 48.86, 2.35),
        city(String(localized: "Berlin"), 52.52, 13.40),
        city(String(localized: "Madrid"), 40.42, -3.70),
        city(String(localized: "Roma"), 41.90, 12.50),
        city(String(localized: "Amsterdam"), 52.37, 4.90),
        city(String(localized: "Viyana"), 48.21, 16.37),
        city(String(localized: "Atina"), 37.98, 23.73),
        city(String(localized: "Moskova"), 55.76, 37.62),
        city(String(localized: "Kahire"), 30.04, 31.24),
        city(String(localized: "Dubai"), 25.20, 55.27),
        city(String(localized: "Riyad"), 24.71, 46.68),
        city(String(localized: "Tahran"), 35.69, 51.39),
        city(String(localized: "Bağdat"), 33.31, 44.37),
        city(String(localized: "Bakü"), 40.41, 49.87),
        city(String(localized: "Delhi"), 28.61, 77.21),
        city(String(localized: "Mumbai"), 19.08, 72.88),
        city(String(localized: "Karaçi"), 24.86, 67.01),
        city(String(localized: "Pekin"), 39.90, 116.41),
        city(String(localized: "Şanghay"), 31.23, 121.47),
        city(String(localized: "Hong Kong"), 22.32, 114.17),
        city(String(localized: "Seul"), 37.57, 126.98),
        city(String(localized: "Tokyo"), 35.68, 139.69),
        city(String(localized: "Singapur"), 1.35, 103.82),
        city(String(localized: "Bangkok"), 13.76, 100.50),
        city(String(localized: "Cakarta"), -6.21, 106.85),
        city(String(localized: "Sidney"), -33.87, 151.21),
        city(String(localized: "New York"), 40.71, -74.01),
        city(String(localized: "Los Angeles"), 34.05, -118.24),
        city(String(localized: "Chicago"), 41.88, -87.63),
        city(String(localized: "Toronto"), 43.65, -79.38),
        city(String(localized: "Mexico City"), 19.43, -99.13),
        city(String(localized: "Sao Paulo"), -23.55, -46.63),
        city(String(localized: "Buenos Aires"), -34.60, -58.38),
        city(String(localized: "Lagos"), 6.52, 3.38),
        city(String(localized: "Johannesburg"), -26.20, 28.05),
        city(String(localized: "Nairobi"), -1.29, 36.82),
        city(String(localized: "Stockholm"), 59.33, 18.07),
        city(String(localized: "Varşova"), 52.23, 21.01),
        city(String(localized: "Lizbon"), 38.72, -9.14),
    ]
}
