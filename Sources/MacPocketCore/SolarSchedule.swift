import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
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

// MARK: - Colour temperature and night curve

public enum ColorTemperature {
    /// Per-channel multipliers (0…1) for a white point of `kelvin`
    /// (Tanner Helland approximation). 6500 K and above is neutral; below 1900 K is clamped.
    public static func channelFactors(kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        guard kelvin < 6500 else { return (1, 1, 1) }
        let t = max(kelvin, 1900) / 100
        let green = 99.4708025861 * log(t) - 161.1195681661
        let blue = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func unit(_ v: Double) -> Double { min(max(v / 255, 0), 1) }
        return (1, unit(green), unit(blue))
    }
}

public enum ColorMethod: String, Codable, CaseIterable, Sendable {
    case macPocket, nightShift
}

public struct NightSettings: Codable, Equatable, Sendable {
    public var nightLevel = 0.6
    public var nightKelvin = 3400.0
    public var transitionMinutes = 60
    public var dimBrightness = true
    public var warmColor = true
    public var colorMethod: ColorMethod = .macPocket
    /// Per display (by identifier): the brightness each display had before night dimming.
    public var baseLevels: [String: Double] = [:]
    public var location: Coordinate?
    public var locationName: String?
    public var pausedUntil: Date?
    public var excludedApps: [String] = []
    public var pauseForFullScreenVideo = false

    public init() {}

    // Missing keys fall back to defaults so records saved by earlier versions still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NightSettings()
        nightLevel = try c.decodeIfPresent(Double.self, forKey: .nightLevel) ?? d.nightLevel
        nightKelvin = try c.decodeIfPresent(Double.self, forKey: .nightKelvin) ?? d.nightKelvin
        transitionMinutes = try c.decodeIfPresent(Int.self, forKey: .transitionMinutes) ?? d.transitionMinutes
        dimBrightness = try c.decodeIfPresent(Bool.self, forKey: .dimBrightness) ?? d.dimBrightness
        warmColor = try c.decodeIfPresent(Bool.self, forKey: .warmColor) ?? d.warmColor
        colorMethod = try c.decodeIfPresent(ColorMethod.self, forKey: .colorMethod) ?? d.colorMethod
        baseLevels = try c.decodeIfPresent([String: Double].self, forKey: .baseLevels) ?? d.baseLevels
        location = try c.decodeIfPresent(Coordinate.self, forKey: .location)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? d.excludedApps
        pauseForFullScreenVideo = try c.decodeIfPresent(Bool.self, forKey: .pauseForFullScreenVideo) ?? d.pauseForFullScreenVideo
    }
}

public struct NightTarget: Equatable, Sendable {
    /// 0 = day … 1 = night.
    public var night: Double
    /// Multiplier for each display's base level.
    public var level: Double
    public var kelvin: Double

    public init(night: Double, level: Double, kelvin: Double) {
        self.night = night
        self.level = level
        self.kelvin = kelvin
    }
}

public enum NightCurve {
    private static let neutralKelvin = 6500.0
    private static let sunriseHalfWindow: TimeInterval = 15 * 60

    public static func target(at date: Date, day: SolarDay, settings: NightSettings) -> NightTarget {
        let night: Double
        switch day {
        case .alwaysDay: night = 0
        case .alwaysNight: night = 1
        case let .normal(sunrise, sunset):
            let half = Double(max(settings.transitionMinutes, 0)) * 60 / 2
            let morningStart = sunrise.addingTimeInterval(-sunriseHalfWindow)
            let morningEnd = sunrise.addingTimeInterval(sunriseHalfWindow)
            let eveningStart = sunset.addingTimeInterval(-half)
            let eveningEnd = sunset.addingTimeInterval(half)
            if date < morningEnd {
                night = 1 - progress(date, from: morningStart, to: morningEnd)
            } else {
                night = progress(date, from: eveningStart, to: eveningEnd)
            }
        }
        return NightTarget(
            night: night,
            level: 1 - night * (1 - settings.nightLevel),
            kelvin: neutralKelvin - night * (neutralKelvin - settings.nightKelvin))
    }

    /// The end of the transition `date` is in, or of the next one on `day`; nil once the evening transition
    /// is over (the next one belongs to the following day) and on polar days, which have none.
    public static func transitionEnd(after date: Date, day: SolarDay, settings: NightSettings) -> Date? {
        guard case let .normal(sunrise, sunset) = day else { return nil }
        let half = Double(max(settings.transitionMinutes, 0)) * 60 / 2
        return [sunrise.addingTimeInterval(sunriseHalfWindow), sunset.addingTimeInterval(half)].first { $0 > date }
    }

    /// Whether a manual brightness change at `date` becomes the display's base level (day, paused, or
    /// brightness not dimmed) rather than holding brightness until the current or next transition ends.
    /// Decided from the curve at `date` itself, not from the last evaluation.
    public static func manualChangeIsBase(at date: Date, day: SolarDay, settings: NightSettings, paused: Bool) -> Bool {
        paused || !settings.dimBrightness || settings.location == nil || target(at: date, day: day, settings: settings).night == 0
    }

    /// Smoothstep of how far `date` is between `start` and `end`.
    private static func progress(_ date: Date, from start: Date, to end: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return date >= end ? 1 : 0 }
        let x = min(max(date.timeIntervalSince(start) / span, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// Whether night mode is lifted right now by one of the optional exceptions.
public enum NightPause {
    public static func isPaused(now: Date, settings: NightSettings, frontmostBundleID: String?, fullScreenVideo: Bool) -> Bool {
        if let until = settings.pausedUntil, until > now { return true }
        if let frontmostBundleID, settings.excludedApps.contains(frontmostBundleID) { return true }
        return fullScreenVideo && settings.pauseForFullScreenVideo
    }
}

/// Which process's display-sleep assertion counts as the front app playing video. Browsers often take it from
/// a helper process (Chromium's GPU/renderer helpers inside the app bundle, WebKit's out-of-process helpers
/// for Safari).
public enum VideoAssertionOwner {
    /// - Parameters:
    ///   - pid: the process holding the assertion; `onBehalfOfPID` the process it says it acts for, if any.
    ///   - path: the holder's executable path; `processName` its name.
    ///   - frontPID / frontBundlePath / frontBundleID: the frontmost application.
    ///   - ownPID: MacPocket itself, whose assertions never count.
    public static func belongsToFrontApp(pid: Int32, onBehalfOfPID: Int32?, path: String?, processName: String?,
                                         frontPID: Int32, frontBundlePath: String?, frontBundleID: String?,
                                         ownPID: Int32) -> Bool {
        guard pid != ownPID, onBehalfOfPID != ownPID else { return false }
        if pid == frontPID || onBehalfOfPID == frontPID { return true }
        if let path, let bundle = frontBundlePath, !bundle.isEmpty {
            let prefix = bundle.hasSuffix("/") ? bundle : bundle + "/"
            if path.hasPrefix(prefix) { return true }
        }
        // Safari's media runs in system WebKit helpers outside its bundle.
        if frontBundleID?.hasPrefix("com.apple.Safari") == true, let processName, processName.hasPrefix("com.apple.WebKit.") {
            return true
        }
        return false
    }
}
