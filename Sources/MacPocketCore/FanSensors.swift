import Foundation
import IOKit

/// One fan as reported by the System Management Controller.
public struct FanSnapshot: Codable, Sendable, Equatable {
    public let rpm: Double
    public let minimumRPM: Double?
    public let maximumRPM: Double?

    public init(rpm: Double, minimumRPM: Double?, maximumRPM: Double?) {
        self.rpm = rpm
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }

    /// Share of the fan's maximum speed, 0…1; nil when the SMC reports no maximum.
    public var fraction: Double? {
        guard let maximumRPM, maximumRPM > 0 else { return nil }
        return min(1, max(0, rpm / maximumRPM))
    }
}

/// Decodes raw SMC key payloads. The SMC reports a four-character type with each key; Apple silicon
/// uses little-endian floats ("flt ") for fan speeds, Intel Macs fixed-point "fpe2".
enum SMCValue {
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count == 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "fpe2":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count == 4 else { return nil }
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    static func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func string(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? ""
    }
}

/// The AppleSMC user client: opens the connection once and reads or writes keys. Writing needs root; reading
/// doesn't. Key metadata is cached, so a read costs one SMC call.
public final class AppleSMCTransport: SMCTransport, @unchecked Sendable {
    /// Mirrors the kernel's `SMCKeyData_t` (80 bytes). Swift lays a nested struct out by its size, not
    /// its stride, so the key info carries its C tail padding explicitly.
    private struct Parameters {
        struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PowerLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
        struct KeyInfo {
            var dataSize: UInt32 = 0, dataType: UInt32 = 0
            var attributes: UInt8 = 0
            var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
        }
        var key: UInt32 = 0
        var version = Version()
        var powerLimit = PowerLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleEventSelector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let writeBytesCommand: UInt8 = 6
    private static let readKeyInfoCommand: UInt8 = 9
    private static let maximumPayload = 32

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: (size: UInt32, type: String)] = [:]

    /// Nil when the SMC can't be reached.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(connection) }

    public func read(_ key: String) throws -> SMCKeyValue? {
        lock.lock()
        defer { lock.unlock() }
        let code = SMCValue.fourCharCode(key)
        guard let info = info(for: code), info.size <= UInt32(Self.maximumPayload) else { return nil }
        var request = Parameters()
        request.key = code
        request.keyInfo.dataSize = info.size
        request.command = Self.readBytesCommand
        guard let reply = call(request) else { return nil }
        let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(info.size))) }
        return SMCKeyValue(type: info.type, bytes: bytes)
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        lock.lock()
        defer { lock.unlock() }
        let code = SMCValue.fourCharCode(key)
        guard let info = info(for: code) else { throw FanControlError.keyMissing(key) }
        guard Int(info.size) == bytes.count, bytes.count <= Self.maximumPayload else { throw FanControlError.writeRefused(key) }
        var request = Parameters()
        request.key = code
        request.keyInfo.dataSize = info.size
        request.command = Self.writeBytesCommand
        withUnsafeMutableBytes(of: &request.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        guard call(request) != nil else { throw FanControlError.writeRefused(key) }
    }

    private func info(for code: UInt32) -> (size: UInt32, type: String)? {
        if let cached = keyInfo[code] { return cached }
        var request = Parameters()
        request.key = code
        request.command = Self.readKeyInfoCommand
        guard let reply = call(request) else { return nil }
        let info = (reply.keyInfo.dataSize, SMCValue.string(reply.keyInfo.dataType))
        keyInfo[code] = info
        return info
    }

    private func call(_ request: Parameters) -> Parameters? {
        var input = request
        var output = Parameters()
        var outputSize = MemoryLayout<Parameters>.stride
        let status = IOConnectCallStructMethod(connection, Self.handleEventSelector, &input, MemoryLayout<Parameters>.stride,
                                               &output, &outputSize)
        return status == kIOReturnSuccess && output.result == 0 ? output : nil
    }
}

/// Reads fan speeds (read-only; no privileges needed outside the sandbox). Fan ranges are cached, so a
/// sample costs one SMC call per fan. Returns nil when the SMC can't be reached, an empty array on Macs
/// without fans.
final class FanSensor {
    private let transport: AppleSMCTransport?
    private var ranges: [Int: (minimum: Double?, maximum: Double?)] = [:]
    private var fanCount: Int?

    init() { transport = AppleSMCTransport() }

    func sample() -> [FanSnapshot]? {
        guard transport != nil else { return nil }
        if fanCount == nil { fanCount = read("FNum").map { Int($0) } }
        guard let count = fanCount else { return nil }
        return (0..<count).compactMap { index in
            guard let rpm = read("F\(index)Ac") else { return nil }
            if ranges[index] == nil { ranges[index] = (read("F\(index)Mn"), read("F\(index)Mx")) }
            return FanSnapshot(rpm: max(0, rpm), minimumRPM: ranges[index]?.minimum, maximumRPM: ranges[index]?.maximum)
        }
    }

    /// Whole-system power in watts on Apple silicon: total draw (PSTR) and DC input (PDTR, which includes
    /// conversion losses). Nil where the SMC does not publish them, e.g. Intel Macs.
    func power() -> (system: Double?, input: Double?) {
        guard transport != nil else { return (nil, nil) }
        func watts(_ key: String) -> Double? { read(key).flatMap { Self.plausibleWatts.contains($0) ? $0 : nil } }
        return (watts("PSTR"), watts("PDTR"))
    }

    static let plausibleWatts = 0.01...2000.0

    private func read(_ key: String) -> Double? {
        guard let value = try? transport?.read(key) else { return nil }
        return SMCValue.decode(type: value.type, bytes: value.bytes)
    }
}
