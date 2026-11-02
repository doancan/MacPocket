import Foundation

/// One SMC key as the controller sees it: the four-character type and the raw bytes.
public struct SMCKeyValue: Equatable, Sendable {
    public let type: String
    public let bytes: [UInt8]

    public init(type: String, bytes: [UInt8]) { self.type = type; self.bytes = bytes }
}

/// The SMC as the fan controller needs it. The real one talks to the AppleSMC user client; tests use a fake.
public protocol SMCTransport: Sendable {
    /// Nil when the key doesn't exist on this Mac.
    func read(_ key: String) throws -> SMCKeyValue?
    func write(_ key: String, bytes: [UInt8]) throws
}

public enum FanControlError: Error, Equatable, Sendable {
    case noSuchFan
    case keyMissing(String)
    case writeRefused(String)
    /// The SMC accepted the target but the fan never moved toward it.
    case noMovement(fan: Int)
}

/// Sets and releases fan targets through the SMC. Every manual speed is verified by reading the actual RPM
/// back; a fan that doesn't follow is handed back to the system.
public final class FanController: @unchecked Sendable {
    private let transport: SMCTransport
    private let sleep: @Sendable (TimeInterval) -> Void

    static let pollInterval: TimeInterval = 0.25
    static let maximumWait: TimeInterval = 5
    /// How close, in RPM, counts as having reached the target, and the least improvement that counts as moving.
    static let reachedTolerance = 100.0
    static let leastProgress = 50.0

    public init(transport: SMCTransport, sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.transport = transport
        self.sleep = sleep
    }

    public var fanCount: Int {
        (try? transport.read("FNum")).flatMap { $0 }.flatMap { SMCValue.decode(type: $0.type, bytes: $0.bytes) }.map(Int.init) ?? 0
    }

    public func range(fan: Int) throws -> ClosedRange<Double> {
        guard fan >= 0, fan < fanCount else { throw FanControlError.noSuchFan }
        guard let minimum = try number("F\(fan)Mn"), let maximum = try number("F\(fan)Mx"), minimum <= maximum else {
            throw FanControlError.keyMissing("F\(fan)Mn/Mx")
        }
        return minimum...maximum
    }

    public func actualRPM(fan: Int) throws -> Double? { try number("F\(fan)Ac") }

    /// Switches the fan to manual mode at `rpm` (clamped to its range) and waits until it follows.
    public func setTarget(fan: Int, rpm: Double) throws {
        let range = try range(fan: fan)
        let target = min(max(rpm, range.lowerBound), range.upperBound)
        let start = try actualRPM(fan: fan) ?? target
        do {
            if try transport.read("Ftst") != nil { try transport.write("Ftst", bytes: [1]) }
            try transport.write("F\(fan)Md", bytes: [1])
            try transport.write("F\(fan)Tg", bytes: Self.encode(Float(target)))
            try waitForFan(fan, start: start, target: target)
        } catch {
            try? release(fan: fan)
            throw error
        }
    }

    /// Hands one fan back to the system's own control.
    public func release(fan: Int) throws {
        guard fan >= 0, fan < fanCount else { throw FanControlError.noSuchFan }
        try transport.write("F\(fan)Md", bytes: [0])
    }

    /// Releases every fan, carrying on past a failure so one stubborn fan can't keep the others manual.
    public func releaseAll() {
        for fan in 0..<fanCount { try? release(fan: fan) }
        if (try? transport.read("Ftst")) != nil { try? transport.write("Ftst", bytes: [0]) }
    }

    private func waitForFan(_ fan: Int, start: Double, target: Double) throws {
        var waited = 0.0
        while true {
            if let actual = try actualRPM(fan: fan) {
                let distance = abs(actual - target)
                if distance <= Self.reachedTolerance || distance <= abs(start - target) - Self.leastProgress { return }
            }
            guard waited < Self.maximumWait else { throw FanControlError.noMovement(fan: fan) }
            sleep(Self.pollInterval)
            waited += Self.pollInterval
        }
    }

    private func number(_ key: String) throws -> Double? {
        try transport.read(key).flatMap { SMCValue.decode(type: $0.type, bytes: $0.bytes) }
    }

    static func encode(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }
}
