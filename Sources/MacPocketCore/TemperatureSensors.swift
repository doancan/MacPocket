import Foundation
import IOKit

/// One temperature sensor reading. `name` is the sensor's own identifier (e.g. "PMU tdie3"),
/// made unique per snapshot.
public struct TemperatureReading: Codable, Sendable, Equatable {
    public let name: String
    public let celsius: Double

    public init(name: String, celsius: Double) {
        self.name = name; self.celsius = celsius
    }
}

/// Where a sensor sits, derived from the names Apple silicon publishes.
public enum TemperatureGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    /// SoC dies (CPU and GPU clusters): "PMU tdie…".
    case soc
    /// Power management unit and board sensors: "PMU tdev…", "PMU TP…".
    case pmu
    /// SSD controller: "NAND CH0 temp".
    case storage
    case battery
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .soc: String(localized: "SoC kalıpları")
        case .pmu: String(localized: "Güç yönetimi (PMU)")
        case .storage: String(localized: "SSD")
        case .battery: String(localized: "Pil")
        case .other: String(localized: "Diğer")
        }
    }

    /// nil for sensors that do not report a temperature of the Mac ("tcal" is a fixed calibration value).
    static func classify(_ name: String) -> TemperatureGroup? {
        let lowered = name.lowercased()
        if lowered.contains("tcal") { return nil }
        if lowered.contains("tdie") { return .soc }
        if lowered.hasPrefix("pmu") { return .pmu }
        if lowered.contains("nand") { return .storage }
        if lowered.contains("battery") { return .battery }
        return .other
    }
}

public struct TemperatureGroupSummary: Sendable, Equatable, Identifiable {
    public let group: TemperatureGroup
    public let maximum: Double
    public let average: Double
    public let count: Int
    public var id: TemperatureGroup { group }
}

public enum TemperatureSummary {
    /// Per-group maximum and average, in `TemperatureGroup` order; groups without readings are left out.
    public static func groups(_ readings: [TemperatureReading]) -> [TemperatureGroupSummary] {
        let grouped = Dictionary(grouping: readings) { TemperatureGroup.classify($0.name) }
        return TemperatureGroup.allCases.compactMap { group in
            guard let values = grouped[group]?.map(\.celsius), let maximum = values.max() else { return nil }
            return TemperatureGroupSummary(group: group, maximum: maximum,
                                           average: values.reduce(0, +) / Double(values.count), count: values.count)
        }
    }
}

/// Reads temperature sensors through the IOHIDEventSystem, the interface Apple silicon publishes them on
/// (the same one iStat Menus and Stats use). The client functions are not in the public headers, so they
/// are resolved at runtime; when any is missing (or on Intel Macs without such sensors) `sample()` is nil.
final class TemperatureSensor {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias ClientSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias ClientCopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias ServiceCopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias ServiceCopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias EventGetFloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField = Int32(15 << 16)
    /// Apple vendor page / temperature sensor usage.
    private static let appleVendorUsagePage = 0xFF00, temperatureUsage = 5
    /// Values outside this range are sensor errors, not temperatures.
    static let plausibleRange = 1.0...150.0

    private let copyProperty: ServiceCopyProperty?
    private let copyEvent: ServiceCopyEvent?
    private let floatValue: EventGetFloatValue?
    /// Sensors with their names, resolved once: the set is fixed for the hardware.
    private var services: [(name: String, service: AnyObject)] = []
    /// The services belong to this client; it must outlive them.
    private var client: AnyObject?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        func resolve<T>(_ symbol: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, symbol) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        copyProperty = resolve("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self)
        copyEvent = resolve("IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self)
        floatValue = resolve("IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
        guard let create = resolve("IOHIDEventSystemClientCreate", as: ClientCreate.self),
              let setMatching = resolve("IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self),
              let copyServices = resolve("IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self),
              let copyProperty,
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        self.client = client
        setMatching(client, ["PrimaryUsagePage": Self.appleVendorUsagePage, "PrimaryUsage": Self.temperatureUsage] as CFDictionary)
        let found = copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        services = found.map { service in
            (copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? "", service)
        }
    }

    func sample() -> [TemperatureReading]? {
        guard let copyEvent, let floatValue, !services.isEmpty else { return nil }
        let raw = services.compactMap { sensor -> (String, Double)? in
            guard let event = copyEvent(sensor.service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { return nil }
            return (sensor.name, floatValue(event, Self.temperatureField))
        }
        return Self.readings(from: raw)
    }

    /// Drops implausible values and calibration sensors, numbers repeated names ("PMU tdie1", "PMU tdie1 2")
    /// so each row is distinct, and sorts naturally ("tdie2" before "tdie10").
    static func readings(from raw: [(name: String, celsius: Double)]) -> [TemperatureReading] {
        var seen: [String: Int] = [:]
        return raw
            .filter { !$0.name.isEmpty && plausibleRange.contains($0.celsius) && TemperatureGroup.classify($0.name) != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { sensor in
                let occurrence = seen[sensor.name, default: 0] + 1
                seen[sensor.name] = occurrence
                return TemperatureReading(name: occurrence == 1 ? sensor.name : "\(sensor.name) \(occurrence)",
                                          celsius: sensor.celsius)
            }
    }
}

/// The hottest CPU/GPU/SoC sensor right now, for the fan helper's thermal guard.
public final class HottestTemperatureReader: @unchecked Sendable {
    private let sensor = TemperatureSensor()

    public init() {}

    /// Nil when no sensor can be read; callers must treat that as "unknown", never as "cool".
    public func celsius() -> Double? { sensor.sample()?.map(\.celsius).max() }
}
