import Foundation
import IOKit

/// One device from the IOKit USB tree (`IOUSBHostDevice`).
public struct USBDevice: Identifiable, Equatable, Sendable {
    public let id: UInt64
    /// The nearest USB device above this one (normally a hub); nil when it sits on a Mac port.
    public let parentID: UInt64?
    public let name: String
    public let vendor: String?
    public let vendorID: Int
    public let productID: Int
    /// Negotiated link speed in bits per second.
    public let linkSpeed: Int64?
    /// Power the Mac granted the device, in milliamps.
    public let powerMilliamps: Int?
    public let deviceClass: Int
    /// `bInterfaceClass` of the device's interfaces (8 = mass storage, 3 = HID, …).
    public let interfaceClasses: Set<Int>

    public init(id: UInt64, parentID: UInt64?, name: String, vendor: String?, vendorID: Int, productID: Int,
                linkSpeed: Int64?, powerMilliamps: Int?, deviceClass: Int, interfaceClasses: Set<Int>) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.vendor = vendor
        self.vendorID = vendorID
        self.productID = productID
        self.linkSpeed = linkSpeed
        self.powerMilliamps = powerMilliamps
        self.deviceClass = deviceClass
        self.interfaceClasses = interfaceClasses
    }

    /// Builds a device from an `IOUSBHostDevice` property dictionary.
    public init(id: UInt64, parentID: UInt64?, properties: [String: Any], interfaceClasses: Set<Int>) {
        func string(_ keys: String...) -> String? {
            keys.lazy.compactMap { (properties[$0] as? String)?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        }
        func int(_ key: String) -> Int? { (properties[key] as? NSNumber)?.intValue }
        let vendorID = int("idVendor") ?? 0, productID = int("idProduct") ?? 0
        let speed: Int64? = (properties["UsbLinkSpeed"] as? NSNumber)?.int64Value
            ?? int("Device Speed").flatMap(USBDevice.speed(forDeviceSpeedCode:))
        self.init(id: id, parentID: parentID,
                  name: string("USB Product Name", "kUSBProductString")
                      ?? String(localized: "USB aygıtı \(String(format: "%04X:%04X", vendorID, productID))"),
                  vendor: string("USB Vendor Name", "kUSBVendorString"),
                  vendorID: vendorID, productID: productID, linkSpeed: speed.flatMap { $0 > 0 ? $0 : nil },
                  powerMilliamps: int("UsbPowerSinkAllocation").flatMap { $0 > 0 ? $0 : nil },
                  deviceClass: int("bDeviceClass") ?? 0, interfaceClasses: interfaceClasses)
    }

    /// Older systems only publish IOKit's speed code.
    static func speed(forDeviceSpeedCode code: Int) -> Int64? {
        switch code {
        case 0: 1_500_000
        case 1: 12_000_000
        case 2: 480_000_000
        case 3: 5_000_000_000
        case 4: 10_000_000_000
        case 5: 20_000_000_000
        default: nil
        }
    }

    public var isHub: Bool { deviceClass == 9 }
    public var isStorage: Bool { interfaceClasses.contains(8) }

    /// Storage on a USB 2 link is limited to ~40 MB/s: usually a slow cable, port or adapter.
    public var isSlowStorage: Bool { isStorage && (linkSpeed ?? .max) <= 480_000_000 }

    /// "USB 3 · 5 Gb/s" style label for the negotiated link.
    public var speedTitle: String? {
        guard let linkSpeed else { return nil }
        let rate = USBDevice.formatRate(linkSpeed)
        return switch linkSpeed {
        case ..<480_000_000: String(localized: "USB 1 · \(rate)")
        case ..<5_000_000_000: String(localized: "USB 2 · \(rate)")
        case ..<40_000_000_000: String(localized: "USB 3 · \(rate)")
        default: String(localized: "USB4 · \(rate)")
        }
    }

    static func formatRate(_ bitsPerSecond: Int64) -> String {
        if bitsPerSecond >= 1_000_000_000 {
            let value = Double(bitsPerSecond) / 1_000_000_000
            return String(localized: "\(value.formatted(.number.precision(.fractionLength(0...1)))) Gb/s")
        }
        let value = Double(bitsPerSecond) / 1_000_000
        return String(localized: "\(value.formatted(.number.precision(.fractionLength(0...1)))) Mb/s")
    }
}

/// A device with its depth below the Mac port, in display order.
public struct USBTreeRow: Identifiable, Equatable, Sendable {
    public let device: USBDevice
    public let depth: Int
    public var id: UInt64 { device.id }
}

public enum USBTree {
    /// Parents before their children, siblings by name. Devices whose parent is missing become roots.
    /// Without hubs, a hub's children take its place in the tree.
    public static func rows(_ devices: [USBDevice], includeHubs: Bool = true) -> [USBTreeRow] {
        let known = Set(devices.map(\.id))
        let children = Dictionary(grouping: devices) { device in device.parentID.flatMap { known.contains($0) ? $0 : nil } }
        var rows: [USBTreeRow] = []
        func visit(_ parent: UInt64?, depth: Int) {
            let sorted = (children[parent] ?? []).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.id < $1.id)
            }
            for device in sorted {
                if !includeHubs, device.isHub {
                    visit(device.id, depth: depth)
                } else {
                    rows.append(USBTreeRow(device: device, depth: depth))
                    visit(device.id, depth: depth + 1)
                }
            }
        }
        visit(nil, depth: 0)
        return rows
    }
}

public enum USBDeviceReader {
    /// Walks every `IOUSBHostDevice`; reading needs no special rights.
    public static func read() -> [USBDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [USBDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let id = entryID(service) else { continue }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any] else { continue }
            devices.append(USBDevice(id: id, parentID: parentDeviceID(service), properties: dictionary,
                                     interfaceClasses: interfaceClasses(service)))
        }
        return devices
    }

    private static func entryID(_ entry: io_registry_entry_t) -> UInt64? {
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS ? id : nil
    }

    private static func parentDeviceID(_ service: io_registry_entry_t) -> UInt64? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<32 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
            if IOObjectConformsTo(parent, "IOUSBHostDevice") != 0 { return entryID(parent) }
        }
        return nil
    }

    private static func interfaceClasses(_ service: io_registry_entry_t) -> Set<Int> {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var classes: Set<Int> = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
               let value = IORegistryEntryCreateCFProperty(child, "bInterfaceClass" as CFString, kCFAllocatorDefault, 0)?
                   .takeRetainedValue() as? NSNumber {
                classes.insert(value.intValue)
            }
        }
        return classes
    }
}

// MARK: - Thunderbolt / USB4

public struct ThunderboltDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let vendor: String?
    /// Link speed in Gb/s as reported by System Information.
    public let speedGbps: Double?
    public let depth: Int
}

public struct ThunderboltPort: Identifiable, Equatable, Sendable {
    public let id: String
    /// Port number as macOS counts receptacles.
    public let receptacle: String?
    public let speedGbps: Double?
    public let devices: [ThunderboltDevice]
    public var isConnected: Bool { !devices.isEmpty }
}

public enum ThunderboltReport {
    public static let executable = "/usr/sbin/system_profiler"
    public static let arguments = ["SPThunderboltDataType", "-json"]

    /// Parses `system_profiler SPThunderboltDataType -json`: one bus per Mac port, chained devices under
    /// `_items`.
    public static func parse(_ data: Data) -> [ThunderboltPort] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buses = root["SPThunderboltDataType"] as? [[String: Any]] else { return [] }
        return buses.enumerated().map { index, bus in
            let receptacle = bus["receptacle_1_tag"] as? [String: Any]
            var devices: [ThunderboltDevice] = []
            func collect(_ items: [[String: Any]], depth: Int) {
                for item in items {
                    let tag = item["receptacle_upstream_tag"] as? [String: Any] ?? item["receptacle_1_tag"] as? [String: Any]
                    let name = (item["device_name_key"] as? String) ?? (item["_name"] as? String) ?? String(localized: "Thunderbolt aygıtı")
                    devices.append(ThunderboltDevice(id: (item["switch_uid_key"] as? String) ?? "\(index)-\(devices.count)",
                                                     name: name, vendor: item["vendor_name_key"] as? String,
                                                     speedGbps: (tag?["current_speed_key"] as? String).flatMap(gigabits), depth: depth))
                    collect(item["_items"] as? [[String: Any]] ?? [], depth: depth + 1)
                }
            }
            collect(bus["_items"] as? [[String: Any]] ?? [], depth: 0)
            return ThunderboltPort(id: (bus["switch_uid_key"] as? String) ?? (bus["_name"] as? String) ?? "\(index)",
                                   receptacle: receptacle?["receptacle_id_key"] as? String,
                                   speedGbps: (receptacle?["current_speed_key"] as? String).flatMap(gigabits),
                                   devices: devices)
        }
        .sorted { ($0.receptacle ?? $0.id).localizedStandardCompare($1.receptacle ?? $1.id) == .orderedAscending }
    }

    /// "Up to 40 Gb/s" / "40 Gb/s x2" → 40. The text is English regardless of the system language.
    static func gigabits(_ text: String) -> Double? {
        guard let range = text.range(of: #"[0-9]+(\.[0-9]+)?(?=\s*Gb/s)"#, options: .regularExpression) else { return nil }
        return Double(text[range])
    }
}
