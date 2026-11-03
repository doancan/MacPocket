import CoreGraphics
import Foundation
import IOKit

// MARK: - Gamma

/// Pure per-channel gamma math: a calibrated curve times the color-warmth factor times the brightness scale.
public enum GammaComposer {
    public static func compose(_ channel: [Float], factor: Float, scale: Float) -> [Float] {
        channel.map { $0 * factor * scale }
    }
}

// MARK: - DDC/CI packets

/// VESA DDC/CI "VCP" codes MacPocket reads and writes.
public enum VCPCode: UInt8, Sendable {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
    /// 1 = muted, 2 = unmuted.
    case audioMute = 0x8D
}

/// Builds and checks DDC/CI messages. The host writes to I2C address 0x37 (0x6E on the wire) with
/// sub-address 0x51; every message ends with an XOR checksum over the addresses and payload.
public enum DDCPacket {
    static let destination: UInt8 = 0x6E
    static let source: UInt8 = 0x51
    /// Replies are checksummed against the virtual host address 0x50.
    static let replyHost: UInt8 = 0x50

    /// "Get VCP Feature" request.
    public static func getRequest(_ code: VCPCode) -> [UInt8] {
        finish([0x80 | 2, 0x01, code.rawValue])
    }

    /// "Set VCP Feature" request.
    public static func setRequest(_ code: VCPCode, value: UInt16) -> [UInt8] {
        finish([0x80 | 4, 0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func finish(_ payload: [UInt8]) -> [UInt8] {
        payload + [payload.reduce(destination ^ source, ^)]
    }

    /// Parses a "Get VCP Feature" reply: [0x6E, 0x88, 0x02, result, code, type, maxHi, maxLo, curHi, curLo, checksum].
    /// Returns nil for errors, unsupported codes, a different code or a bad checksum.
    public static func parseReply(_ bytes: [UInt8], expecting code: VCPCode) -> (current: UInt16, maximum: UInt16)? {
        guard bytes.count >= 11, bytes[1] & 0x7F >= 8, bytes[2] == 0x02, bytes[3] == 0x00, bytes[4] == code.rawValue else { return nil }
        let checksum = bytes[0..<10].reduce(replyHost, ^)
        guard checksum == bytes[10] else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        guard maximum > 0 else { return nil }
        return (min(current, maximum), maximum)
    }
}

// MARK: - Matching displays to I2C channels

/// A display as the I/O registry describes it, with whether a DDC channel hangs under it.
public struct RegistryDisplay: Equatable, Sendable {
    public let vendor: UInt32
    public let product: UInt32
    public let serial: UInt32
    /// Registry entry ID of the DCPAVServiceProxy under this display, if any.
    public let avServiceID: UInt64?

    public init(vendor: UInt32, product: UInt32, serial: UInt32, avServiceID: UInt64?) {
        self.vendor = vendor; self.product = product; self.serial = serial; self.avServiceID = avServiceID
    }
}

public enum DisplayMatcher {
    /// Pairs each CoreGraphics display with the registry display carrying the same vendor, product and serial;
    /// when two identical monitors report no serial, the remaining ones are paired in registry order.
    public static func match(_ displays: [(id: CGDirectDisplayID, vendor: UInt32, product: UInt32, serial: UInt32)],
                             registry: [RegistryDisplay]) -> [CGDirectDisplayID: UInt64] {
        var result: [CGDirectDisplayID: UInt64] = [:]
        var available = registry.filter { $0.avServiceID != nil }
        for display in displays {
            if let index = available.firstIndex(where: { $0.vendor == display.vendor && $0.product == display.product
                && $0.serial == display.serial && display.serial != 0 }) {
                result[display.id] = available.remove(at: index).avServiceID
            }
        }
        for display in displays where result[display.id] == nil {
            if let index = available.firstIndex(where: { $0.vendor == display.vendor && $0.product == display.product }) {
                result[display.id] = available.remove(at: index).avServiceID
            }
        }
        return result
    }
}

// MARK: - Brightness arithmetic

public enum BrightnessStep {
    /// macOS moves brightness in sixteenths; ⌥⇧ with the keys moves in quarters of that.
    public static let normal = 1.0 / 16
    public static let fine = 1.0 / 64

    /// The next level, snapped to the step grid like the built-in display, clamped to 0…1.
    public static func next(from level: Double, up: Bool, step: Double) -> Double {
        let index = (level / step).rounded()
        let target = (index + (up ? 1 : -1)) * step
        return min(1, max(0, target))
    }

    /// Filled segments of the 16-segment brightness indicator.
    public static func chiclets(_ level: Double) -> (filled: UInt32, total: UInt32) {
        (UInt32((min(1, max(0, level)) * 64).rounded()), 64)
    }
}

/// A brightness key press. Laptops deliver the keys as system-defined media events; Macs with only external
/// displays deliver the same Magic Keyboard keys as ordinary key events with their own key codes.
public enum BrightnessKey: Equatable, Sendable {
    case up, down

    public var isUp: Bool { self == .up }

    /// Ordinary key event (desktop Macs): 144 is brightness up, 145 brightness down.
    public init?(keyCode: Int64) {
        switch keyCode {
        case 144: self = .up
        case 145: self = .down
        default: return nil
        }
    }

    /// System-defined event of subtype 8 (aux control button): NX_KEYTYPE_BRIGHTNESS_UP is 2, _DOWN is 3.
    public init?(systemDefinedSubtype subtype: Int, data1: Int) {
        guard subtype == 8 else { return nil }
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 2: self = .up
        case 3: self = .down
        default: return nil
        }
    }

    public static func isSystemDefinedKeyDown(data1: Int) -> Bool { (data1 & 0xFF00) >> 8 == 0xA }
}

// MARK: - Hardware access (Apple silicon)

/// DDC over the IOAVService I2C bridge Apple silicon exposes for external displays (USB-C, DisplayPort and,
/// since macOS 13, the HDMI port). The functions are exported by IOKit without headers, so they are looked
/// up at run time; when missing, `isAvailable` is false and callers fall back to software dimming.
public final class DDCChannel: @unchecked Sendable {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    /// Loaded once and never changed.
    nonisolated(unsafe) private static let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let create: Create? = library.flatMap { dlsym($0, "IOAVServiceCreateWithService") }.map { unsafeBitCast($0, to: Create.self) }
    private static let write: Transfer? = library.flatMap { dlsym($0, "IOAVServiceWriteI2C") }.map { unsafeBitCast($0, to: Transfer.self) }
    private static let read: Transfer? = library.flatMap { dlsym($0, "IOAVServiceReadI2C") }.map { unsafeBitCast($0, to: Transfer.self) }

    public static var isAvailable: Bool { create != nil && write != nil && read != nil }

    private let service: CFTypeRef
    /// I2C transactions to one display must not overlap.
    private let queue: DispatchQueue

    nonisolated(unsafe) private static var sharedChannels: [UInt64: DDCChannel] = [:]
    private static let sharedLock = NSLock()

    /// The one channel for this registry entry in this process. Brightness and volume share it, so their I2C
    /// transactions to the same monitor run on one queue instead of interleaving and garbling each other's replies.
    public static func shared(registryID: UInt64) -> DDCChannel? {
        sharedLock.withLock {
            if let existing = sharedChannels[registryID] { return existing }
            let channel = DDCChannel(registryID: registryID)
            sharedChannels[registryID] = channel
            return channel
        }
    }

    /// `registryID` is the DCPAVServiceProxy entry found by `DisplayRegistry.scan()`.
    public init?(registryID: UInt64) {
        guard let create = Self.create, let matching = IORegistryEntryIDMatching(registryID) else { return nil }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { return nil }
        self.service = service
        queue = DispatchQueue(label: "MacPocket.ddc.\(registryID)")
    }

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    /// Reads a VCP value. Monitors drop the odd transaction, so each read is tried a few times.
    public func get(_ code: VCPCode, attempts: Int = 4) -> (current: UInt16, maximum: UInt16)? {
        queue.sync {
            guard let write = Self.write, let read = Self.read else { return nil }
            for _ in 0..<attempts {
                var request = DDCPacket.getRequest(code)
                guard write(service, Self.chipAddress, Self.dataAddress, &request, UInt32(request.count)) == kIOReturnSuccess else {
                    usleep(20_000); continue
                }
                usleep(50_000) // DDC/CI: the display needs ~40 ms before it can answer
                var reply = [UInt8](repeating: 0, count: 12)
                guard read(service, Self.chipAddress, 0, &reply, UInt32(reply.count)) == kIOReturnSuccess else { usleep(20_000); continue }
                if let value = DDCPacket.parseReply(reply, expecting: code) { return value }
                usleep(20_000)
            }
            return nil
        }
    }

    @discardableResult
    public func set(_ code: VCPCode, value: UInt16, attempts: Int = 2) -> Bool {
        queue.sync {
            guard let write = Self.write else { return false }
            var request = DDCPacket.setRequest(code, value: value)
            for _ in 0..<attempts {
                // Some monitors miss the first write after idling; sending it twice is harmless.
                if write(service, Self.chipAddress, Self.dataAddress, &request, UInt32(request.count)) == kIOReturnSuccess {
                    usleep(10_000)
                    return true
                }
                usleep(20_000)
            }
            return false
        }
    }
}

/// Walks the I/O registry for displays (AppleCLCD2 framebuffers with product attributes) and the external
/// DDC channel beneath each.
public enum DisplayRegistry {
    public static func scan() -> [RegistryDisplay] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var displays: [RegistryDisplay] = []
        var pending: (vendor: UInt32, product: UInt32, serial: UInt32)?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(entry, &className)
            let name = String(cString: className)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                if let pending { displays.append(RegistryDisplay(vendor: pending.vendor, product: pending.product, serial: pending.serial, avServiceID: nil)) }
                pending = productAttributes(entry)
            } else if name == "DCPAVServiceProxy", let current = pending,
                      (IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) == "External" {
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(entry, &id)
                displays.append(RegistryDisplay(vendor: current.vendor, product: current.product, serial: current.serial, avServiceID: id))
                pending = nil
            }
        }
        if let pending { displays.append(RegistryDisplay(vendor: pending.vendor, product: pending.product, serial: pending.serial, avServiceID: nil)) }
        return displays
    }

    private static func productAttributes(_ entry: io_registry_entry_t) -> (vendor: UInt32, product: UInt32, serial: UInt32)? {
        guard let attributes = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any] else { return nil }
        func number(_ key: String) -> UInt32 { (product[key] as? NSNumber)?.uint32Value ?? 0 }
        return (number("LegacyManufacturerID"), number("ProductID"), number("SerialNumber"))
    }
}

// MARK: - Schedule

/// Brightness by time of day: levels at chosen times with straight-line fades between them, wrapping past
/// midnight.
public struct BrightnessSchedule: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Hashable, Identifiable, Sendable {
        public var id: Int { minute }
        /// Minutes after midnight, 0…1439.
        public var minute: Int
        /// 0…1.
        public var level: Double

        public init(minute: Int, level: Double) {
            self.minute = min(max(minute, 0), 1439)
            self.level = min(max(level, 0), 1)
        }
    }

    public enum Source: String, Codable, Sendable {
        case manual, solar
    }

    public var enabled = false
    /// nil = manual (older saved schedules).
    public var source: Source?
    public var night: NightSettings?
    public var points: [Point] = [Point(minute: 7 * 60, level: 1), Point(minute: 19 * 60, level: 0.8), Point(minute: 22 * 60 + 30, level: 0.5)]

    public init() {}

    private var sorted: [Point] { points.sorted { $0.minute < $1.minute } }

    /// The level for a minute of the day; nil without points.
    public func level(at minute: Int) -> Double? {
        let points = sorted
        guard let first = points.first, let last = points.last else { return nil }
        guard points.count > 1 else { return first.level }
        let minute = ((minute % 1440) + 1440) % 1440
        // The segment that contains `minute`, the last one wrapping to the first point of the next day.
        let previous = points.last { $0.minute <= minute } ?? last
        let next = points.first { $0.minute > minute } ?? first
        let span = ((next.minute - previous.minute) % 1440 + 1440) % 1440
        guard span > 0 else { return previous.level }
        let elapsed = ((minute - previous.minute) % 1440 + 1440) % 1440
        return previous.level + (next.level - previous.level) * Double(elapsed) / Double(span)
    }

    /// The next point after `minute`, where a manual override ends.
    public func nextPoint(after minute: Int) -> Int? {
        let points = sorted
        return (points.first { $0.minute > minute } ?? points.first)?.minute
    }
}
