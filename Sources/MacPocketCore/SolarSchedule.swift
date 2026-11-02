import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Sunrise and sunset of one local calendar day.
public enum SolarDay: Equatable, Sendable {
    case normal(sunrise: Date, sunset: Date)
    /// The sun does not set (midnight sun).
    case alwaysDay
    /// The sun does not rise (polar night).
    case alwaysNight
}

/// NOAA solar position formulas, official zenith 90.833°.
public enum SolarCalculator {
    /// The sunrise and sunset of the local calendar day (in `timeZone`) that contains `date`.
    public static func day(containing date: Date, at coordinate: Coordinate, timeZone: TimeZone) -> SolarDay {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) else {
            return .alwaysNight
        }

        // Julian day at 12:00 UTC of that civil date (Unix epoch is JD 2440587.5).
        let julianDay = midnight.timeIntervalSince1970 / 86400 + 2440587.5 + 0.5
        let t = (julianDay - 2451545.0) / 36525.0
        let rad = Double.pi / 180

        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(meanAnomaly * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * meanAnomaly * rad) * (0.019993 - 0.000101 * t)
            + sin(3 * meanAnomaly * rad) * 0.000289
        let trueLongitude = meanLongitude + center
        let apparent = trueLongitude - 0.00569 - 0.00478 * sin((125.04 - 1934.136 * t) * rad)
        let obliquityMean = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = obliquityMean + 0.00256 * cos((125.04 - 1934.136 * t) * rad)
        let declination = asin(sin(obliquity * rad) * sin(apparent * rad))

        let y = pow(tan(obliquity * rad / 2), 2)
        let equationOfTime = 4 / rad * (y * sin(2 * meanLongitude * rad)
            - 2 * eccentricity * sin(meanAnomaly * rad)
            + 4 * eccentricity * y * sin(meanAnomaly * rad) * cos(2 * meanLongitude * rad)
            - 0.5 * y * y * sin(4 * meanLongitude * rad)
            - 1.25 * eccentricity * eccentricity * sin(2 * meanAnomaly * rad))

        let latitude = coordinate.latitude * rad
        let cosHourAngle = cos(90.833 * rad) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)
        if cosHourAngle > 1 { return .alwaysNight }
        if cosHourAngle < -1 { return .alwaysDay }
        let hourAngle = acos(cosHourAngle) / rad

        // Minutes after 00:00 UTC of the civil date.
        let sunriseMinutes = 720 - 4 * (coordinate.longitude + hourAngle) - equationOfTime
        let sunsetMinutes = 720 - 4 * (coordinate.longitude - hourAngle) - equationOfTime
        return .normal(sunrise: midnight.addingTimeInterval(sunriseMinutes * 60),
                       sunset: midnight.addingTimeInterval(sunsetMinutes * 60))
    }
}
