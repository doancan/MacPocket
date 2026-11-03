import Foundation

/// A connected Bluetooth accessory and its battery, merged from the I/O Registry (Magic keyboards, trackpads, mice)
/// and `system_profiler SPBluetoothDataType` (names, kinds, and AirPods' left/right/case levels).
public struct BluetoothBatteryDevice: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case keyboard, trackpad, mouse, headphones, other }

    public struct Levels: Equatable, Sendable {
        public var main: Int?
        public var left: Int?
        public var right: Int?
        public var batteryCase: Int?
        public init(main: Int? = nil, left: Int? = nil, right: Int? = nil, batteryCase: Int? = nil) {
            self.main = main; self.left = left; self.right = right; self.batteryCase = batteryCase
        }
        public var isEmpty: Bool { main == nil && left == nil && right == nil && batteryCase == nil }
        /// The level that runs out first; the case only counts when nothing else is known.
        public var lowest: Int? { [main, left, right].compactMap { $0 }.min() ?? batteryCase }
    }

    /// Normalized "64:A5:C3:F1:7B:96".
    public let address: String
    public var name: String
    public var kind: Kind
    public var levels: Levels
    public var charging = false
    /// The level couldn't be read (e.g. a Logitech device before Input Monitoring is allowed).
    public var levelUnavailable: Bool { levels.isEmpty }

    public var id: String { address }

    public init(address: String, name: String, kind: Kind, levels: Levels, charging: Bool = false) {
        self.address = address; self.name = name; self.kind = kind; self.levels = levels; self.charging = charging
    }
}

public enum BluetoothBatteryParser {
    /// "64-a5-c3-f1-7b-96" and "64:A5:C3:F1:7B:96" → "64:A5:C3:F1:7B:96".
    public static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    public static func kind(minorType: String?) -> BluetoothBatteryDevice.Kind {
        let type = (minorType ?? "").lowercased()
        if type.contains("keyboard") { return .keyboard }
        if type.contains("trackpad") { return .trackpad }
        if type.contains("mouse") { return .mouse }
        if type.contains("headphone") || type.contains("headset") || type.contains("earbud") { return .headphones }
        return .other
    }

    /// "85%" or "85" → 85.
    static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return (value as? NSNumber)?.intValue }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    /// Connected devices from `system_profiler -json SPBluetoothDataType`, with any battery levels it reports.
    public static func connectedDevices(fromSystemProfiler data: Data) -> [BluetoothBatteryDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BluetoothBatteryDevice] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any], let address = info["device_address"] as? String else { continue }
                    let levels = BluetoothBatteryDevice.Levels(main: percent(info["device_batteryLevelMain"]),
                                                               left: percent(info["device_batteryLevelLeft"]),
                                                               right: percent(info["device_batteryLevelRight"]),
                                                               batteryCase: percent(info["device_batteryLevelCase"]))
                    devices.append(BluetoothBatteryDevice(address: normalize(address), name: name,
                                                          kind: kind(minorType: info["device_minorType"] as? String), levels: levels))
                }
            }
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Fills in levels read over HID++ by product name ("MX Master"): Logitech's Bluetooth HID interface doesn't carry
    /// the Bluetooth address. Devices the profiler didn't list are added.
    public static func merge(_ devices: [BluetoothBatteryDevice], logitech: [(name: String, kind: BluetoothBatteryDevice.Kind, reading: HIDPPBattery.Reading)])
        -> [BluetoothBatteryDevice] {
        var result = devices
        for entry in logitech {
            let wanted = entry.name.lowercased()
            if let index = result.firstIndex(where: { $0.name.lowercased() == wanted })
                ?? result.firstIndex(where: { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) }) {
                result[index].levels.main = entry.reading.percent
                result[index].charging = entry.reading.charging
            } else {
                result.append(BluetoothBatteryDevice(address: "logitech:" + entry.name, name: entry.name, kind: entry.kind,
                                                     levels: .init(main: entry.reading.percent), charging: entry.reading.charging))
            }
        }
        return result
    }

    /// The profiler's devices with the registry's levels filled in (the registry wins for the main level: it updates
    /// live, the profiler's snapshot may be minutes old). Registry devices the profiler doesn't list as connected — a
    /// Magic accessory charging over its cable is a USB device then — are added under their product's name.
    public static func merge(_ devices: [BluetoothBatteryDevice], registry: [String: RegistryBattery]) -> [BluetoothBatteryDevice] {
        var result = devices.map { device in
            var device = device
            if let entry = registry[device.address] {
                device.levels.main = entry.level
                if entry.wired { device.charging = true }
            }
            return device
        }
        let listed = Set(devices.map(\.address))
        for (address, entry) in registry.sorted(by: { $0.key < $1.key }) where !listed.contains(address) {
            let product = AppleAccessory.named(productID: entry.productID)
            result.append(BluetoothBatteryDevice(address: address, name: product.name, kind: product.kind,
                                                 levels: .init(main: entry.level), charging: entry.wired))
        }
        return result
    }
}

/// One accessory's battery as the I/O Registry reports it.
public struct RegistryBattery: Equatable, Sendable {
    public var level: Int
    public var productID: Int
    /// Connected by cable (USB): it is charging.
    public var wired: Bool
    public init(level: Int, productID: Int, wired: Bool) { self.level = level; self.productID = productID; self.wired = wired }
}

/// Names for Apple's Magic accessories by USB/Bluetooth product ID, for when nothing else names them.
public enum AppleAccessory {
    public static func named(productID: Int) -> (name: String, kind: BluetoothBatteryDevice.Kind) {
        switch productID {
        case 0x0265, 0x0314, 0x0324: ("Magic Trackpad", .trackpad)
        case 0x0269, 0x030D, 0x0323: ("Magic Mouse", .mouse)
        case 0x0267, 0x026C, 0x029A, 0x029C, 0x029F, 0x0320, 0x0321, 0x0322: ("Magic Keyboard", .keyboard)
        default: (String(localized: "Bluetooth aygıtı"), .other)
        }
    }
}

/// Low-battery notifications: once when a device drops to `threshold`, again only after it was charged above `rearm`.
public struct LowBatteryAlerts: Equatable, Sendable {
    public var threshold: Int
    public var rearm: Int
    private var notified: Set<String> = []

    public init(threshold: Int = 20, rearm: Int = 30) {
        self.threshold = threshold
        self.rearm = max(rearm, threshold + 1)
    }

    /// The devices to notify about now.
    public mutating func evaluate(_ devices: [BluetoothBatteryDevice]) -> [BluetoothBatteryDevice] {
        var due: [BluetoothBatteryDevice] = []
        for device in devices {
            guard let level = device.levels.lowest else { continue }
            if level <= threshold, !notified.contains(device.address) {
                notified.insert(device.address)
                due.append(device)
            } else if level >= rearm {
                notified.remove(device.address)
            }
        }
        return due
    }
}

// MARK: - Logitech HID++ 2.0

/// Logitech's HID++ 2.0 battery features, spoken over the device's vendor HID collection (usage page 0xFF43).
/// Bluetooth devices answer as device index 0xFF; every request is a 20-byte "long" report with ID 0x11.
public enum HIDPPBattery {
    public static let longReportID: UInt8 = 0x11
    public static let directDevice: UInt8 = 0xFF
    /// Our software ID in the low nibble of the function byte, so replies to us can be told from the device's own events.
    static let softwareID: UInt8 = 0x1

    /// Battery features, most informative first.
    public enum Feature: UInt16, CaseIterable, Sendable {
        case unifiedBattery = 0x1004
        case batteryStatus = 0x1000
        case batteryVoltage = 0x1001

        /// The function that reports the level: UnifiedBattery's get_status is function 1, the others function 0.
        var levelFunction: UInt8 { self == .unifiedBattery ? 1 : 0 }
    }

    public struct Reading: Equatable, Sendable {
        public var percent: Int
        public var charging: Bool
    }

    private static func packet(featureIndex: UInt8, function: UInt8, parameters: [UInt8] = []) -> [UInt8] {
        let head: [UInt8] = [longReportID, directDevice, featureIndex, (function << 4) | softwareID]
        return Array((head + parameters).prefix(20)) + [UInt8](repeating: 0, count: max(0, 20 - head.count - parameters.count))
    }

    /// Root (index 0) GetFeature: asks which index the device gives `feature`.
    public static func featureRequest(_ feature: Feature) -> [UInt8] {
        packet(featureIndex: 0, function: 0, parameters: [UInt8(feature.rawValue >> 8), UInt8(feature.rawValue & 0xFF)])
    }

    public static func levelRequest(_ feature: Feature, index: UInt8) -> [UInt8] {
        packet(featureIndex: index, function: feature.levelFunction)
    }

    /// Whether `reply` answers our request to `featureIndex`/`function` (and isn't the device's own notification).
    static func answers(_ reply: [UInt8], featureIndex: UInt8, function: UInt8) -> Bool {
        reply.count >= 7 && (reply[0] == longReportID || reply[0] == 0x10) && reply[1] == directDevice
            && reply[2] == featureIndex && reply[3] == (function << 4) | softwareID
    }

    /// The feature's index from a GetFeature reply; nil when unsupported (index 0) or not our reply.
    public static func featureIndex(from reply: [UInt8]) -> UInt8? {
        guard answers(reply, featureIndex: 0, function: 0), reply[4] != 0 else { return nil }
        return reply[4]
    }

    /// The battery from a level reply of `feature` at `index`.
    public static func reading(from reply: [UInt8], feature: Feature, index: UInt8) -> Reading? {
        guard answers(reply, featureIndex: index, function: feature.levelFunction) else { return nil }
        switch feature {
        case .unifiedBattery:
            // [state of charge %, level flags, charging status (1 charging, 2 slow, 3 full, 4 error)]
            guard reply[4] <= 100 else { return nil }
            return Reading(percent: Int(reply[4]), charging: (1...3).contains(reply[6]))
        case .batteryStatus:
            // [discharge level %, next level %, status (0 discharging, 1–4 charging/full)]
            guard reply[4] <= 100 else { return nil }
            return Reading(percent: Int(reply[4]), charging: (1...4).contains(reply[6]))
        case .batteryVoltage:
            // [voltage mV hi, lo, flags (bit 7: external power)]
            let millivolts = Int(reply[4]) << 8 | Int(reply[5])
            guard millivolts > 0 else { return nil }
            return Reading(percent: percent(millivolts: millivolts), charging: reply[6] & 0x80 != 0)
        }
    }

    /// A single-cell Li-ion discharge curve, roughly as Logitech's own software maps it.
    public static func percent(millivolts: Int) -> Int {
        let curve: [(Int, Int)] = [(4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50),
                                   (3778, 40), (3751, 30), (3717, 20), (3671, 10), (3500, 0)]
        if millivolts >= curve[0].0 { return 100 }
        for (upper, lower) in zip(curve, curve.dropFirst()) where millivolts >= lower.0 {
            let span = Double(upper.0 - lower.0)
            return lower.1 + Int((Double(millivolts - lower.0) / span * Double(upper.1 - lower.1)).rounded())
        }
        return 0
    }
}
