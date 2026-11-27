import Foundation

/// What the privileged helper exposes to MacPocket. Replies carry an error message on failure, nil on
/// success.
@objc(FanHelperXPC) public protocol MacPocketHelperXPC {
    /// One entry per fan: actual RPM, minimum, maximum.
    func status(reply: @escaping @Sendable ([[NSNumber]], String?) -> Void)
    func setTarget(fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void)
    /// Keeps manual speeds alive; without one every 15 s the helper hands the fans back to the system.
    func heartbeat(reply: @escaping @Sendable () -> Void)
    func releaseAll(reply: @escaping @Sendable () -> Void)
    /// Discovers MACs on one validated /22–/30 subnet. No shell command is accepted from the client.
    func scanMACAddresses(cidr: String, interface: String, reply: @escaping @Sendable ([String: String], String?) -> Void)
}

public enum MacPocketHelperConstants {
    // These are persistent installation identities, despite the helper now serving more than fan control.
    // Changing them creates a different service and discards the wizard's existing authorization.
    public static let machServiceName = "com.doancan.MacPocket.FanHelper"
    public static let daemonPlistName = "com.doancan.MacPocket.FanHelper.plist"
    /// The app sends a heartbeat this often while a manual profile is active.
    public static let heartbeatInterval: TimeInterval = 5
    /// The helper releases the fans after this long without one.
    public static let heartbeatTimeout: TimeInterval = 15
}

/// The helper's own check of every request, independent of whatever the app already clamped.
public struct FanRequestValidator: Sendable {
    private let ranges: [ClosedRange<Double>]

    public init(fans: [ClosedRange<Double>]) { ranges = fans }

    public func validate(fan: Int, rpm: Double) throws {
        guard ranges.indices.contains(fan) else { throw FanControlError.noSuchFan }
        guard rpm.isFinite, ranges[fan].contains(rpm) else { throw FanControlError.writeRefused("F\(fan)Tg") }
    }
}

/// Stops manual fan speeds when the machine runs hot and only allows them again once it has cooled.
public struct ThermalGuard: Sendable {
    public static let tripCelsius = 90.0
    public static let resumeCelsius = 80.0
    private var tripped = false

    public init() {}

    public mutating func allowsManual(hottestCelsius: Double) -> Bool {
        if hottestCelsius >= Self.tripCelsius { tripped = true }
        else if hottestCelsius < Self.resumeCelsius { tripped = false }
        return !tripped
    }

    /// Consecutive failed sensor reads tolerated before the guard gives up on supervising.
    public static let unreadableLimit = 5
    private var unreadable = 0

    /// For the watchdog, where a read can fail. A sensor that stays unreadable counts as tripped: the guard
    /// can no longer protect the machine, so the fans go back to the system.
    public mutating func allowsManual(reading: Double?) -> Bool {
        guard let reading else {
            unreadable += 1
            if unreadable >= Self.unreadableLimit { tripped = true }
            return !tripped
        }
        unreadable = 0
        return allowsManual(hottestCelsius: reading)
    }
}
