import Foundation
import IOKit

/// The NVMe SMART / Health Information log page (log 02h, 512 bytes).
public struct NVMeHealth: Equatable, Sendable {
    public let criticalWarning: UInt8
    public let temperatureCelsius: Double?
    /// Percent of spare blocks left, and the level below which the drive reports a warning.
    public let availableSpare: Int
    public let spareThreshold: Int
    /// The vendor's estimate of rated life used; may exceed 100.
    public let percentageUsed: Int
    public let bytesRead: Double
    public let bytesWritten: Double
    public let powerCycles: UInt64
    public let powerOnHours: UInt64
    public let unsafeShutdowns: UInt64
    public let mediaErrors: UInt64
    public let errorLogEntries: UInt64

    /// One "data unit" is 1000 × 512 bytes.
    static let dataUnitBytes = 512_000.0

    public init?(log: [UInt8]) {
        guard log.count >= 192 else { return nil }
        func counter(_ offset: Int) -> UInt64 {
            // 128-bit little-endian counters; the upper half is never reached in practice, so saturate.
            if log[(offset + 8)..<(offset + 16)].contains(where: { $0 != 0 }) { return .max }
            return (0..<8).reduce(UInt64(0)) { $0 | UInt64(log[offset + $1]) << (8 * UInt64($1)) }
        }
        criticalWarning = log[0]
        let kelvin = Int(log[1]) | Int(log[2]) << 8
        temperatureCelsius = kelvin > 0 ? Double(kelvin) - 273.15 : nil
        availableSpare = Int(log[3])
        spareThreshold = Int(log[4])
        percentageUsed = Int(log[5])
        bytesRead = Double(counter(32)) * Self.dataUnitBytes
        bytesWritten = Double(counter(48)) * Self.dataUnitBytes
        powerCycles = counter(112)
        powerOnHours = counter(128)
        unsafeShutdowns = counter(144)
        mediaErrors = counter(160)
        errorLogEntries = counter(176)
    }

    /// Rated life left, as the drive itself estimates it.
    public var lifeRemaining: Int { max(0, 100 - percentageUsed) }

    public var assessment: DiskHealthAssessment {
        var findings: [String] = []
        var level = DiskHealthAssessment.Level.good
        func raise(_ to: DiskHealthAssessment.Level, _ text: String) {
            findings.append(text)
            if to.rawValue > level.rawValue { level = to }
        }
        if criticalWarning & 0x01 != 0 || availableSpare < spareThreshold {
            raise(.critical, String(localized: "Yedek blok oranı güvenli sınırın altına indi."))
        }
        if criticalWarning & 0x02 != 0 { raise(.attention, String(localized: "Disk sıcaklığı güvenli aralığın dışında.")) }
        if criticalWarning & 0x04 != 0 { raise(.critical, String(localized: "Disk, güvenilirliğinin düştüğünü bildiriyor.")) }
        if criticalWarning & 0x08 != 0 { raise(.critical, String(localized: "Disk salt okunur moda geçti.")) }
        if percentageUsed >= 100 {
            raise(.critical, String(localized: "Üreticinin öngördüğü yazma ömrü doldu."))
        } else if percentageUsed >= 80 {
            raise(.attention, String(localized: "Üreticinin öngördüğü yazma ömrünün %\(percentageUsed) kadarı kullanıldı."))
        }
        if mediaErrors > 0 { raise(.attention, String(localized: "Diskte \(mediaErrors) okunamayan veri hatası kayıtlı.")) }
        return DiskHealthAssessment(level: level, findings: findings)
    }
}

public struct DiskHealthAssessment: Equatable, Sendable {
    public enum Level: Int, Sendable { case good, attention, critical }
    public let level: Level
    public let findings: [String]

    public var title: String {
        switch level {
        case .good: String(localized: "Sağlıklı")
        case .attention: String(localized: "Dikkat")
        case .critical: String(localized: "Kritik")
        }
    }
}

public struct DiskHealthReading: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let model: String
    public let firmware: String?
    public let capacityBytes: Int64?
    public let health: NVMeHealth
}

public enum DiskHealthReader {
    private static var userClientType: CFUUID { CFUUIDCreateFromString(nil, "AA0FA6F9-C2D6-457F-B10B-59A13253292F" as CFString)! }
    private static var smartInterface: CFUUID { CFUUIDCreateFromString(nil, "CCD1DB19-FD9A-4DAF-BF95-12454B230AB6" as CFString)! }
    private static var plugInInterface: CFUUID { CFUUIDCreateFromString(nil, "C244E858-109C-11D4-91D4-0050E4C6426F" as CFString)! }

    /// `IONVMeSMARTInterface` vtable: the IUnknown header (reserved, QueryInterface, AddRef, Release),
    /// a version/revision word, then `SMARTReadData(self, nvme_smart_log *)`.
    private static let smartReadDataSlot = 5
    private typealias SMARTReadData = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Int32

    /// Reads every NVMe drive that publishes `NVMe SMART Capable` (Apple's internal SSDs and most NVMe drives).
    /// Works without administrator rights. External USB enclosures normally don't pass SMART through.
    public static func read() -> [DiskHealthReading] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var readings: [DiskHealthReading] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard property(service, "NVMe SMART Capable") as? Bool == true,
                  let log = smartLog(service), let health = NVMeHealth(log: log) else { continue }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            let characteristics = property(service, "Device Characteristics") as? [String: Any]
            let model = (searchUp(service, "Model Number") as? String) ?? (characteristics?["Product Name"] as? String)
            let firmware = (searchUp(service, "Firmware Revision") as? String) ?? (characteristics?["Product Revision Level"] as? String)
            readings.append(DiskHealthReading(id: id,
                                              model: model?.trimmingCharacters(in: .whitespaces) ?? String(localized: "NVMe disk"),
                                              firmware: firmware?.trimmingCharacters(in: .whitespaces),
                                              capacityBytes: wholeMediaSize(service), health: health))
        }
        return readings
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func searchUp(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }

    private static func wholeMediaSize(_ service: io_registry_entry_t) -> Int64? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if IOObjectConformsTo(child, "IOMedia") != 0, property(child, "Whole") as? Bool == true,
               let size = property(child, "Size") as? NSNumber {
                return size.int64Value
            }
        }
        return nil
    }

    private static func smartLog(_ service: io_service_t) -> [UInt8]? {
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, userClientType, plugInInterface, &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let vtable = plugIn.pointee?.pointee else { return nil }
        defer { _ = vtable.Release(plugIn) }
        var smart: LPVOID?
        guard vtable.QueryInterface(plugIn, CFUUIDGetUUIDBytes(smartInterface), &smart) == S_OK, let smart else { return nil }
        let table = smart.assumingMemoryBound(to: UnsafePointer<UnsafeRawPointer?>.self).pointee
        defer {
            // IUnknown Release lives in slot 3.
            if let release = table[3] {
                _ = unsafeBitCast(release, to: (@convention(c) (UnsafeMutableRawPointer) -> UInt32).self)(smart)
            }
        }
        guard let function = table[smartReadDataSlot] else { return nil }
        var log = [UInt8](repeating: 0, count: 512)
        let status = log.withUnsafeMutableBytes { unsafeBitCast(function, to: SMARTReadData.self)(smart, $0.baseAddress!) }
        return status == KERN_SUCCESS ? log : nil
    }
}
