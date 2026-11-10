import Darwin
import Foundation
import IOKit
import IOKit.ps

// MARK: - Models

/// One entry of IOPSCopyPowerSourcesList: internal battery, UPS or other external source.
public struct PowerSourceInfo: Identifiable, Equatable, Sendable {
    public var id: String { "\(type)-\(name)" }
    public let name: String
    /// kIOPSInternalBatteryType ("InternalBattery") or kIOPSUPSType ("UPS").
    public let type: String
    public let transport: String?
    /// "AC Power", "Battery Power" or "Off Line".
    public let state: String?
    public let isPresent: Bool
    public let currentCapacity: Int?
    public let maxCapacity: Int?
    public let isCharging: Bool?
    public let isCharged: Bool?
    /// Minutes; nil while macOS is still calculating (-1).
    public let timeToEmptyMinutes: Int?
    public let timeToFullMinutes: Int?
    /// "Good", "Fair", "Poor" (older macOS) or a condition string.
    public let health: String?
    public let healthCondition: String?
    public let maximumCapacityPercent: Int?
    public let optimizedChargingEngaged: Bool?

    public var isUPS: Bool { type == "UPS" }
    public var isInternalBattery: Bool { type == "InternalBattery" }
    public var chargePercent: Double? {
        guard let current = currentCapacity, let max = maxCapacity, max > 0 else { return nil }
        return min(100, Double(current) / Double(max) * 100)
    }

    public init(description: [String: Any]) {
        func int(_ key: String) -> Int? {
            (description[key] as? NSNumber).map(\.intValue)
        }
        func positiveMinutes(_ key: String) -> Int? { int(key).flatMap { $0 >= 0 ? $0 : nil } }
        name = description["Name"] as? String ?? String(localized: "Güç kaynağı")
        type = description["Type"] as? String ?? "Unknown"
        transport = description["Transport Type"] as? String
        state = description["Power Source State"] as? String
        isPresent = (description["Is Present"] as? Bool) ?? true
        currentCapacity = int("Current Capacity")
        maxCapacity = int("Max Capacity")
        isCharging = description["Is Charging"] as? Bool
        isCharged = description["Is Charged"] as? Bool
        timeToEmptyMinutes = positiveMinutes("Time to Empty")
        timeToFullMinutes = positiveMinutes("Time to Full Charge")
        health = description["BatteryHealth"] as? String
        healthCondition = description["BatteryHealthCondition"] as? String
        maximumCapacityPercent = int("Maximum Capacity Percent")
        optimizedChargingEngaged = description["Optimized Battery Charging Engaged"] as? Bool
            ?? (description["Optimized Battery Charging Engaged"] as? NSNumber).map(\.boolValue)
    }
}

/// IOPSCopyExternalPowerAdapterDetails. Desktops typically report only a family code.
public struct PowerAdapterInfo: Equatable, Sendable {
    public let watts: Int?
    public let name: String?
    public let manufacturer: String?
    public let model: String?
    public let serial: String?
    public let voltageMillivolts: Int?
    public let currentMilliamps: Int?
    public let isWireless: Bool?
    public let familyCode: Int?

    public var hasDetails: Bool { watts != nil || name != nil || manufacturer != nil || serial != nil }

    public init(dictionary: [String: Any]) {
        func int(_ key: String) -> Int? { (dictionary[key] as? NSNumber).map(\.intValue) }
        func text(_ key: String) -> String? {
            guard let value = dictionary[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        watts = int("Watts").flatMap { $0 > 0 ? $0 : nil }
        name = text("Name") ?? text("Description")
        manufacturer = text("Manufacturer")
        model = text("Model") ?? (dictionary["Model"] as? NSNumber).map { String(format: "0x%X", $0.intValue) }
        serial = text("SerialString") ?? text("SerialNumber")
        voltageMillivolts = int("AdapterVoltage") ?? int("Voltage")
        currentMilliamps = int("Current")
        isWireless = dictionary["IsWireless"] as? Bool
        familyCode = int("FamilyCode")
    }
}

/// AppleSmartBattery IORegistry properties. Present on every Apple silicon Mac; `installed` tells
/// whether a battery actually exists. `PowerTelemetryData` reports whole-system input power.
public struct BatteryRegistryInfo: Equatable, Sendable {
    public let installed: Bool
    public let cycleCount: Int?
    public let designCapacity: Int?
    /// Full-charge capacity in mAh.
    public let maxCapacity: Int?
    public let currentCapacity: Int?
    public let temperatureCelsius: Double?
    public let voltageMillivolts: Int?
    /// Negative while discharging.
    public let amperageMilliamps: Int?
    public let isCharging: Bool?
    public let externalConnected: Bool?
    public let fullyCharged: Bool?
    public let timeRemainingMinutes: Int?
    public let serial: String?
    public let deviceName: String?
    public let manufacturer: String?
    public let designCycleCount: Int?
    public let permanentFailure: Bool?
    public let notChargingReason: Int?
    /// Whole-system input power (mW), voltage (mV) and current (mA) from PowerTelemetryData.
    public let systemPowerInMilliwatts: Int?
    public let systemVoltageInMillivolts: Int?
    public let systemCurrentInMilliamps: Int?
    public let batteryPowerMilliwatts: Int?
    /// Running sum of SystemPowerIn samples (mW) and its sample count. The instantaneous value is often 0
    /// on desktops, but the delta of these two between reads gives the recent average draw.
    public let accumulatedSystemPowerIn: Int?
    public let systemPowerInSampleCount: Int?

    /// Average whole-system draw (W) between an earlier reading and this one.
    public func averageSystemWatts(since earlier: BatteryRegistryInfo) -> Double? {
        guard let total = accumulatedSystemPowerIn, let count = systemPowerInSampleCount,
              let previousTotal = earlier.accumulatedSystemPowerIn, let previousCount = earlier.systemPowerInSampleCount,
              count > previousCount, total >= previousTotal else { return nil }
        return Double(total - previousTotal) / Double(count - previousCount) / 1000
    }

    public var healthPercent: Double? {
        guard installed, let max = maxCapacity, let design = designCapacity, design > 0, max > 0 else { return nil }
        return Double(max) / Double(design) * 100
    }

    /// Positive while charging, negative while discharging (W).
    public var batteryWatts: Double? {
        guard installed, let volts = voltageMillivolts, let amps = amperageMilliamps, volts > 0 else { return nil }
        return Double(volts) * Double(amps) / 1_000_000
    }

    public init(properties: [String: Any]) {
        func int(_ key: String, in source: [String: Any]? = nil) -> Int? {
            ((source ?? properties)[key] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
        }
        func bool(_ key: String) -> Bool? {
            properties[key] as? Bool ?? (properties[key] as? NSNumber).map(\.boolValue)
        }
        func text(_ key: String) -> String? {
            guard let value = properties[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        let batteryData = properties["BatteryData"] as? [String: Any]
        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        let charger = properties["ChargerData"] as? [String: Any]
        let installed = bool("BatteryInstalled") ?? ((int("DesignCapacity") ?? 0) > 0)
        self.installed = installed
        cycleCount = installed ? int("CycleCount") : nil
        designCapacity = installed ? (int("DesignCapacity") ?? int("DesignCapacity", in: batteryData)) : nil
        // Apple silicon reports MaxCapacity/CurrentCapacity as percentages; raw mAh live in AppleRaw*.
        let rawMax = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity")
        let legacyMax = int("MaxCapacity").flatMap { $0 > 100 ? $0 : nil }
        maxCapacity = installed ? (rawMax ?? legacyMax) : nil
        currentCapacity = installed ? (int("AppleRawCurrentCapacity") ?? int("CurrentCapacity").flatMap { $0 > 100 ? $0 : nil }) : nil
        temperatureCelsius = installed ? int("Temperature").flatMap { $0 > 0 ? Double($0) / 100 : nil } : nil
        voltageMillivolts = installed ? int("Voltage").flatMap { $0 > 0 ? $0 : nil } : nil
        amperageMilliamps = installed ? (int("InstantAmperage") ?? int("Amperage")) : nil
        isCharging = installed ? bool("IsCharging") : nil
        externalConnected = bool("ExternalConnected")
        fullyCharged = installed ? bool("FullyCharged") : nil
        timeRemainingMinutes = installed ? int("TimeRemaining").flatMap { $0 > 0 && $0 < 65_535 ? $0 : nil } : nil
        serial = installed ? text("Serial") ?? text("BatterySerialNumber") : nil
        deviceName = installed ? text("DeviceName") : nil
        manufacturer = installed ? text("Manufacturer") : nil
        designCycleCount = installed ? (int("DesignCycleCount9C") ?? int("DesignCycleCount")) : nil
        permanentFailure = installed ? (int("PermanentFailureStatus").map { $0 != 0 }
                                        ?? int("PermanentFailureStatus", in: batteryData).map { $0 != 0 }) : nil
        notChargingReason = installed ? int("NotChargingReason", in: charger) : nil
        systemPowerInMilliwatts = int("SystemPowerIn", in: telemetry).flatMap { $0 > 0 ? $0 : nil }
        systemVoltageInMillivolts = int("SystemVoltageIn", in: telemetry).flatMap { $0 > 0 ? $0 : nil }
        systemCurrentInMilliamps = int("SystemCurrentIn", in: telemetry).flatMap { $0 > 0 ? $0 : nil }
        batteryPowerMilliwatts = installed ? int("BatteryPower", in: telemetry) : nil
        accumulatedSystemPowerIn = int("AccumulatedSystemPowerIn", in: telemetry)
        systemPowerInSampleCount = int("SystemPowerInAccumulatorCount", in: telemetry)
    }
}

public struct PowerOverview: Equatable, Sendable {
    public let capturedAt: Date
    /// "AC Power", "Battery Power" or "UPS Power".
    public let providingSource: String
    public let sources: [PowerSourceInfo]
    public let adapter: PowerAdapterInfo?
    public let battery: BatteryRegistryInfo?
    public let lowPowerMode: Bool
    public let thermalState: String

    public var internalBattery: PowerSourceInfo? { sources.first(where: \.isInternalBattery) }
    public var upsSources: [PowerSourceInfo] { sources.filter(\.isUPS) }
    /// A battery exists if IOPS lists one or the registry says it is installed.
    public var hasBattery: Bool { internalBattery != nil || battery?.installed == true }

    /// Equal apart from `capturedAt`: the reading has nothing new to show.
    public func hasSameReading(as other: PowerOverview) -> Bool {
        providingSource == other.providingSource && sources == other.sources && adapter == other.adapter
            && battery == other.battery && lowPowerMode == other.lowPowerMode && thermalState == other.thermalState
    }
}

// MARK: - Live readers

public enum PowerInspector {
    public static func overview() -> PowerOverview {
        var providing = "unknown"
        var sources: [PowerSourceInfo] = []
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? "unknown"
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
            for item in list {
                guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any]
                else { continue }
                sources.append(PowerSourceInfo(description: description))
            }
        }
        let adapter = (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])
            .map(PowerAdapterInfo.init(dictionary:))
        return PowerOverview(capturedAt: Date(), providingSource: providing, sources: sources, adapter: adapter,
                             battery: batteryRegistry(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                             thermalState: thermalName(ProcessInfo.processInfo.thermalState))
    }

    public static func batteryRegistry() -> BatteryRegistryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryRegistryInfo(properties: properties)
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

// MARK: - Fixed read-only pmset commands

public enum PMReadCommand: String, CaseIterable, Sendable {
    case custom, live, assertions, thermal, schedule

    public var arguments: [String] {
        switch self {
        case .custom: ["-g", "custom"]
        case .live: ["-g"]
        case .assertions: ["-g", "assertions"]
        case .thermal: ["-g", "therm"]
        case .schedule: ["-g", "sched"]
        }
    }
}

public enum PowerCommandReader {
    /// Runs one fixed `pmset -g …` read without a shell; output bounded to 256 KiB, 8 s timeout.
    public static func read(_ command: PMReadCommand) async throws -> String {
        let runner = SystemDiagnosticCommandRunner(executable: PMSetCommand.executable, arguments: command.arguments,
                                                   separateErrorOutput: true)
        let result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { try runner.execute() }.value
        } onCancel: { runner.cancel() }
        guard result.exitCode == 0 else {
            let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PMSetRunError.failed(code: Int(result.exitCode), message: message.isEmpty ? String(localized: "pmset okunamadı") : message)
        }
        return result.output
    }

    public static func settings() async throws -> (profiles: [PMSettingsProfile], live: PMLiveSettings) {
        async let custom = read(.custom)
        async let live = read(.live)
        return try await (PMSettingsParser.parseCustom(custom), PMSettingsParser.parseLive(live))
    }

    public static func assertions() async throws -> PMAssertionReport { PMAssertionParser.parse(try await read(.assertions)) }
    public static func thermal() async throws -> PMThermalReport { PMThermalParser.parse(try await read(.thermal)) }
    public static func schedule() async throws -> [PMScheduledEvent] { PMScheduleParser.parse(try await read(.schedule)) }

    /// Streams `pmset -g log` (tens of MB, mostly assertion churn) and keeps only the newest `limit`
    /// sleep/wake/display events. Memory stays bounded regardless of log size.
    public static func recentLogEvents(limit: Int = 150, timeout: TimeInterval = 40) async throws -> [PMLogEvent] {
        let reader = PMLogStreamReader(limit: max(1, limit), timeout: timeout)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { try reader.run() }.value
        } onCancel: { reader.cancel() }
    }
}

/// Owns one `pmset -g log` process. Lines are filtered as they arrive; only matches are kept.
final class PMLogStreamReader: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private let limit: Int
    private let timeout: TimeInterval
    private var cancelled = false
    private var timedOut = false

    init(limit: Int, timeout: TimeInterval) {
        self.limit = limit
        self.timeout = timeout
        process.executableURL = URL(fileURLWithPath: PMSetCommand.executable)
        process.arguments = ["-g", "log"]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/usr/sbin:/bin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        terminate()
    }

    private func terminate() {
        if process.isRunning, process.processIdentifier > 1 { Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    func run() throws -> [PMLogEvent] {
        lock.lock(); let early = cancelled; lock.unlock()
        if early { throw CancellationError() }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        try? pipe.fileHandleForWriting.close()
        let deadline = DispatchWorkItem { [self] in
            lock.lock(); timedOut = true; lock.unlock()
            terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }

        var kept: [PMLogEvent] = []
        var carry = Data()
        let handle = pipe.fileHandleForReading
        let assertionsTag = Data("Assertions".utf8)
        func consume(_ line: Data) {
            // Skip the dominant assertion rows by their fixed-offset type column before decoding.
            let typeStart = line.startIndex + 26
            if line.count > typeStart - line.startIndex + assertionsTag.count,
               line[typeStart..<(typeStart + assertionsTag.count)] == assertionsTag { return }
            guard let text = String(data: line, encoding: .utf8), PMLogParser.isCandidate(Substring(text)),
                  let event = PMLogParser.parseLine(text) else { return }
            kept.append(event)
            if kept.count > limit * 2 { kept.removeFirst(kept.count - limit) }
        }
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            carry.append(chunk)
            var start = carry.startIndex
            while let newline = carry[start...].firstIndex(of: UInt8(ascii: "\n")) {
                consume(carry[start..<newline])
                start = carry.index(after: newline)
            }
            carry = Data(carry[start...])
            // A pathological line without newlines must not grow memory without bound.
            if carry.count > 65_536 { carry.removeAll(keepingCapacity: true) }
        }
        if !carry.isEmpty { consume(carry) }
        process.waitUntilExit()
        try? handle.close()
        lock.lock(); let wasCancelled = cancelled; let didTimeOut = timedOut; lock.unlock()
        if wasCancelled { throw CancellationError() }
        if didTimeOut && kept.isEmpty { throw SystemDiagnosticError.timedOut("") }
        return Array(kept.suffix(limit))
    }
}
