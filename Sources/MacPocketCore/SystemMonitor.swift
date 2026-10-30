import Foundation
import Darwin
import IOKit.ps

public struct VolumeSnapshot: Codable, Sendable {
    public let name: String
    public let path: String
    public let totalBytes: Int64
    public let availableBytes: Int64
}

public struct PowerSnapshot: Codable, Sendable {
    public let source: String
    public let batteryPresent: Bool
    public let chargePercent: Double?
    public let isCharging: Bool?
    public let lowPowerMode: Bool
    /// Minutes until empty (on battery) or full (charging); nil while macOS is still estimating.
    public var minutesRemaining: Int? = nil
}

public struct SystemSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let hardwareModel: String
    public let logicalCPUCount: Int
    public let cpuUserPercent: Double?
    public let cpuSystemPercent: Double?
    public let cpuIdlePercent: Double?
    public let physicalMemoryBytes: UInt64
    /// Raw VM free pages, not Activity Monitor's available/reclaimable memory.
    public let freeMemoryBytes: UInt64
    public let wiredMemoryBytes: UInt64
    /// Physical pages occupied by the compressor, not the uncompressed payload size.
    public let compressedMemoryBytes: UInt64
    /// Activity Monitor's "App Memory": anonymous (internal) pages minus purgeable pages.
    public var appMemoryBytes: UInt64? = nil
    /// Swap currently in use on disk (vm.swapusage).
    public var swapUsedBytes: UInt64? = nil
    /// Total swap file capacity (vm.swapusage).
    public var swapTotalBytes: UInt64? = nil
    /// Activity Monitor's "Cached Files": file-backed (external) plus purgeable pages.
    public var cachedFilesBytes: UInt64? = nil
    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical.
    public var memoryPressureLevel: Int? = nil
    /// 100 − kern.memorystatus_level: share of memory the kernel considers under pressure.
    public var memoryPressurePercent: Double? = nil
    /// Busy share of each logical CPU over the sampling interval (user + nice + system).
    public var cpuCorePercents: [Double]? = nil
    /// 1, 5 and 15 minute load averages.
    public var loadAverages: [Double]? = nil
    public var network: NetworkSnapshot? = nil
    public var diskIO: DiskIOSnapshot? = nil
    /// Fans reported by the SMC; empty on fanless Macs, nil when the SMC can't be read.
    public var fans: [FanSnapshot]? = nil
    public let uptimeSeconds: Double
    public let thermalState: String
    public let volumes: [VolumeSnapshot]
    public let power: PowerSnapshot
}

extension SystemSnapshot {
    /// Activity Monitor's "Memory Used": app memory + wired + compressor.
    public var usedMemoryBytes: UInt64? {
        guard let app = appMemoryBytes else { return nil }
        return min(physicalMemoryBytes, app &+ wiredMemoryBytes &+ compressedMemoryBytes)
    }
    public var cpuTotalPercent: Double? {
        guard let user = cpuUserPercent, let system = cpuSystemPercent else { return nil }
        return min(100, max(0, user + system))
    }
}

public enum SystemMonitorError: Error, LocalizedError, Sendable {
    case kernelCall(String, Int32)
    case invalidCPUData
    case hardwareModelUnavailable

    public var errorDescription: String? {
        switch self {
        case let .kernelCall(name, code): return String(localized: "\(name) başarısız (\(code)).")
        case .invalidCPUData: return String(localized: "İşlemci sayaçları okunamadı.")
        case .hardwareModelUnavailable: return String(localized: "Donanım modeli okunamadı.")
        }
    }
}

struct SystemCPUTicks: Equatable, Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

enum SystemCPUDelta {
    /// PROCESSOR_CPU_LOAD_INFO counters are unsigned 32-bit cumulative ticks.
    /// Per-counter wrapping subtraction also handles an ordinary counter rollover.
    static func percentages(previous: [SystemCPUTicks]?, current: [SystemCPUTicks])
        -> (user: Double, system: Double, idle: Double)? {
        guard let previous, !current.isEmpty, previous.count == current.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        for (old, new) in zip(previous, current) {
            user += UInt64(new.user &- old.user) + UInt64(new.nice &- old.nice)
            system += UInt64(new.system &- old.system)
            idle += UInt64(new.idle &- old.idle)
        }
        let total = Double(user + system + idle)
        guard total > 0 else { return nil }
        return (Double(user) / total * 100, Double(system) / total * 100, Double(idle) / total * 100)
    }

    /// Busy percentage (user + nice + system) of each CPU. Nil when the CPU set changed.
    /// A CPU without elapsed ticks (parked core) reports 0.
    static func perCore(previous: [SystemCPUTicks]?, current: [SystemCPUTicks]) -> [Double]? {
        guard let previous, !current.isEmpty, previous.count == current.count else { return nil }
        return zip(previous, current).map { old, new in
            let busy = UInt64(new.user &- old.user) + UInt64(new.nice &- old.nice) + UInt64(new.system &- old.system)
            let total = busy + UInt64(new.idle &- old.idle)
            return total > 0 ? min(100, Double(busy) / Double(total) * 100) : 0
        }
    }
}

public actor SystemMonitor {
    private var previousCPU: [SystemCPUTicks]?
    private var network = NetworkSampler()
    private var diskIO = DiskIOSampler()
    private let fanSensor = FanSensor()

    public init() {}

    public func snapshot() throws -> SystemSnapshot {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let cpu = try Self.cpuTicks(host: host)
        let percentages = SystemCPUDelta.percentages(previous: previousCPU, current: cpu)
        let memory = try Self.memory(host: host)
        let model = try Self.hardwareModel()
        let cores = SystemCPUDelta.perCore(previous: previousCPU, current: cpu)
        previousCPU = cpu
        let swap = Self.swapUsage()
        let pressure = Self.memoryPressure()
        var snapshot = SystemSnapshot(
            capturedAt: Date(), hardwareModel: model, logicalCPUCount: cpu.count,
            cpuUserPercent: percentages?.user, cpuSystemPercent: percentages?.system,
            cpuIdlePercent: percentages?.idle, physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            freeMemoryBytes: memory.free, wiredMemoryBytes: memory.wired,
            compressedMemoryBytes: memory.compressed, appMemoryBytes: memory.app, swapUsedBytes: swap?.used,
            uptimeSeconds: Self.uptime(),
            thermalState: Self.thermalDescription(), volumes: volumes(), power: Self.power()
        )
        snapshot.swapTotalBytes = swap?.total
        snapshot.cachedFilesBytes = memory.cached
        snapshot.memoryPressureLevel = pressure.level
        snapshot.memoryPressurePercent = pressure.percent
        snapshot.cpuCorePercents = cores
        snapshot.loadAverages = Self.loadAverages()
        // Both samplers are a single getifaddrs / IOKit registry pass: cheap enough for every tick.
        snapshot.network = network.sample()
        snapshot.diskIO = diskIO.sample()
        snapshot.fans = fanSensor.sample()
        return snapshot
    }

    private static func loadAverages() -> [Double]? {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : nil
    }

    private static func memoryPressure() -> (level: Int?, percent: Double?) {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let hasLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        var available: Int32 = 0
        size = MemoryLayout<Int32>.size
        let hasAvailable = sysctlbyname("kern.memorystatus_level", &available, &size, nil, 0) == 0
        return (hasLevel ? Int(level) : nil,
                hasAvailable ? min(100, max(0, 100 - Double(available))) : nil)
    }

    private static func cpuTicks(host: host_t) throws -> [SystemCPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS else { throw SystemMonitorError.kernelCall("host_processor_info", result) }
        guard let info else { throw SystemMonitorError.invalidCPUData }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        guard count > 0, Int(infoCount) >= Int(count) * stride else { throw SystemMonitorError.invalidCPUData }
        return (0..<Int(count)).map { index in
            let offset = index * stride
            return SystemCPUTicks(
                user: UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)]))
        }
    }

    private static func memory(host: host_t) throws
        -> (free: UInt64, wired: UInt64, compressed: UInt64, app: UInt64, cached: UInt64) {
        var size: vm_size_t = 0
        let pageResult = host_page_size(host, &size)
        guard pageResult == KERN_SUCCESS else { throw SystemMonitorError.kernelCall("host_page_size", pageResult) }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw SystemMonitorError.kernelCall("host_statistics64", result) }
        let pageSize = UInt64(size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        return (UInt64(stats.free_count) * pageSize, UInt64(stats.wire_count) * pageSize,
                UInt64(stats.compressor_page_count) * pageSize,
                (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize,
                (UInt64(stats.external_page_count) + purgeablePages) * pageSize)
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (usage.xsu_used, usage.xsu_total)
    }

    /// Wall-clock time since boot, including sleep (ProcessInfo.systemUptime excludes sleep).
    private static func uptime() -> Double {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let booted = Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000
        return max(0, Date().timeIntervalSince1970 - booted)
    }

    private static func hardwareModel() throws -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            throw SystemMonitorError.hardwareModelUnavailable
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            throw SystemMonitorError.hardwareModelUnavailable
        }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func thermalDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// Purgeable space per volume. The "important usage" query makes the system size purgeable data
    /// and is far costlier than the other capacity keys, so it is refreshed at most once a minute.
    private var purgeableCache: [String: (bytes: Int64, measuredAt: Date)] = [:]
    private static let purgeableRefreshInterval: TimeInterval = 60

    private func volumes() -> [VolumeSnapshot] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                                        options: [.skipHiddenVolumes]) ?? [URL(fileURLWithPath: "/")]
        let now = Date()
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity,
                  total > 0 else { return nil }
            var purgeable = purgeableCache[url.path]
            if purgeable == nil || now.timeIntervalSince(purgeable!.measuredAt) >= Self.purgeableRefreshInterval {
                // Finder reports "important usage" capacity, which includes purgeable space.
                let important = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage ?? 0
                purgeable = (max(0, important - Int64(available)), now)
                purgeableCache[url.path] = purgeable
            }
            let free = min(Int64(total), Int64(available) + (purgeable?.bytes ?? 0))
            return VolumeSnapshot(name: values.volumeName ?? url.lastPathComponent, path: url.path,
                                  totalBytes: Int64(total), availableBytes: free)
        }.sorted { $0.path < $1.path }
    }

    private static func power() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSnapshot(source: "unknown", batteryPresent: false, chargePercent: nil,
                                 isCharging: nil, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? "unknown"
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in sources {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  (description[kIOPSIsPresentKey] as? Bool) != false else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let percent: Double?
            if let current, let maximum, maximum > 0 {
                percent = min(100, max(0, current / maximum * 100))
            } else { percent = nil }
            let charging = description[kIOPSIsChargingKey] as? Bool
            // -1 means "still calculating"; 0 to empty while on AC is meaningless.
            let minutesKey = charging == true ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (description[minutesKey] as? NSNumber)?.intValue
            var snapshot = PowerSnapshot(source: source, batteryPresent: true, chargePercent: percent,
                                         isCharging: charging,
                                         lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
            snapshot.minutesRemaining = minutes.flatMap { $0 > 0 ? $0 : nil }
            return snapshot
        }
        return PowerSnapshot(source: source, batteryPresent: false, chargePercent: nil, isCharging: nil,
                             lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

public enum DiagnosticCompletion: String, Codable, Sendable {
    case complete, outputLimit, timedOut
}

public struct DiagnosticReport: Codable, Sendable {
    public let id: String
    public let title: String
    public let capturedAt: Date
    public let output: String
    /// Nil when the bounded runner stopped before obtaining a normal result.
    public let exitCode: Int32?
    public let completion: DiagnosticCompletion
    public let partial: Bool
    public let truncated: Bool
}

public enum SystemDiagnostic: String, CaseIterable, Sendable {
    case memoryPressure, swap, powerAssertions, powerSettings, thermal, disks, network, openFiles

    public var title: String {
        switch self {
        case .memoryPressure: return String(localized: "Bellek baskısı")
        case .swap: return String(localized: "Swap kullanımı")
        case .powerAssertions: return String(localized: "Uyku engelleri")
        case .powerSettings: return String(localized: "Güç ayarları")
        case .thermal: return String(localized: "Termal durum")
        case .disks: return String(localized: "Disk ve dosya sistemleri")
        case .network: return String(localized: "Ağ arayüzleri")
        case .openFiles: return String(localized: "Açık dosyalar")
        }
    }

    var command: (executable: String, arguments: [String]) {
        switch self {
        case .memoryPressure: return ("/usr/bin/memory_pressure", ["-Q"])
        case .swap: return ("/usr/sbin/sysctl", ["vm.swapusage"])
        case .powerAssertions: return ("/usr/bin/pmset", ["-g", "assertions"])
        case .powerSettings: return ("/usr/bin/pmset", ["-g", "custom"])
        case .thermal: return ("/usr/bin/pmset", ["-g", "therm"])
        case .disks: return ("/bin/df", ["-k"])
        case .network: return ("/usr/sbin/netstat", ["-ibn"])
        case .openFiles: return ("/usr/sbin/lsof", ["-nP", "-u", String(getuid())])
        }
    }

    func command(processID: Int32?) throws -> (executable: String, arguments: [String]) {
        guard let processID else { return command }
        guard self == .openFiles else {
            throw SystemDiagnosticError.invalidArguments(String(localized: "PID yalnız Açık dosyalar tanılamasında kullanılabilir."))
        }
        guard processID > 0 else {
            throw SystemDiagnosticError.invalidArguments(String(localized: "Açık dosyalar için pozitif bir PID gerekir."))
        }
        return ("/usr/sbin/lsof", ["-nP", "-p", String(processID)])
    }
}

public enum SystemDiagnosticError: Error, LocalizedError, Sendable {
    case timedOut(String)
    case outputLimit(String)
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(output): return String(localized: "Tanılama süresi doldu. Kısmi çıktı:\n\(output)")
        case let .outputLimit(output): return String(localized: "Tanılama çıktısı boyut sınırına ulaştı. Kısmi çıktı:\n\(output)")
        case let .invalidArguments(message): return message
        }
    }
}

public enum SystemDiagnostics {
    /// Runs one fixed, read-only command without a shell. Output is bounded to 256 KiB.
    public static func run(_ diagnostic: SystemDiagnostic, processID: Int32? = nil) async throws -> DiagnosticReport {
        let command = try diagnostic.command(processID: processID)
        let runner = SystemDiagnosticCommandRunner(executable: command.executable, arguments: command.arguments)
        return try await run(diagnostic, runner: runner)
    }

    static func run(_ diagnostic: SystemDiagnostic, runner: SystemDiagnosticCommandRunner) async throws -> DiagnosticReport {
        do {
            let result = try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) { try runner.execute() }.value
            } onCancel: { runner.cancel() }
            return DiagnosticReport(id: diagnostic.rawValue, title: diagnostic.title, capturedAt: Date(),
                                    output: result.output, exitCode: result.exitCode, completion: .complete,
                                    partial: false, truncated: false)
        } catch let SystemDiagnosticError.outputLimit(output) {
            return DiagnosticReport(id: diagnostic.rawValue, title: diagnostic.title, capturedAt: Date(),
                                    output: output, exitCode: nil, completion: .outputLimit,
                                    partial: true, truncated: true)
        } catch let SystemDiagnosticError.timedOut(output) {
            return DiagnosticReport(id: diagnostic.rawValue, title: diagnostic.title, capturedAt: Date(),
                                    output: output, exitCode: nil, completion: .timedOut,
                                    partial: true, truncated: false)
        }
    }
}

/// Owns only its newly launched diagnostic process. No caller-provided shell or PID is accepted.
final class SystemDiagnosticCommandRunner: @unchecked Sendable {
    struct Result: Sendable { let output: String; let errorOutput: String; let exitCode: Int32 }
    private let process = Process()
    private let lock = NSLock()
    private let timeout: TimeInterval
    private let outputLimit: Int
    private let separateErrorOutput: Bool
    private let stopOnOutputLimit: Bool
    private let interruptGracePeriod: TimeInterval?
    private var output = Data()
    private var errorOutput = Data()
    private var cancelled = false
    private var timedOut = false
    private var outputExceeded = false
    private var finished = false
    private var stopRequested = false

    /// - Parameters:
    ///   - separateErrorOutput: Keeps stderr out of `output` so machine-readable stdout stays parseable.
    ///   - stopOnOutputLimit: When false, output beyond the limit is dropped but the process keeps running.
    ///   - interruptGracePeriod: Sends SIGINT first so tools with child processes (brew) can clean up,
    ///     then SIGKILL after the grace period. Nil kills immediately.
    init(executable: String, arguments: [String], timeout: TimeInterval = 8, outputLimit: Int = 262_144,
         environment: [String: String]? = nil, separateErrorOutput: Bool = false,
         stopOnOutputLimit: Bool = true, interruptGracePeriod: TimeInterval? = nil) {
        self.timeout = timeout
        self.outputLimit = outputLimit
        self.separateErrorOutput = separateErrorOutput
        self.stopOnOutputLimit = stopOnOutputLimit
        self.interruptGracePeriod = interruptGracePeriod
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment ?? ["LC_ALL": "C", "PATH": "/usr/bin:/usr/sbin:/bin:/sbin"]
        process.standardInput = FileHandle.nullDevice
    }

    func cancel() {
        lock.lock()
        cancelled = true
        stopOwnedProcessLocked()
        lock.unlock()
    }

    func execute() throws -> Result {
        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        let outputPipe = Pipe()
        let errorPipe = separateErrorOutput ? Pipe() : outputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let pipes = separateErrorOutput ? [outputPipe, errorPipe] : [outputPipe]
        do { try process.run() }
        catch {
            for pipe in pipes {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            throw error
        }
        for pipe in pipes { try? pipe.fileHandleForWriting.close() }
        lock.lock()
        if cancelled { stopOwnedProcessLocked() }
        lock.unlock()

        // Dispatch-driven reads never block a thread on read(2). A grandchild that inherited the
        // pipe can keep it open after our process exits, so the EOF wait below is bounded.
        // A semaphore (not a DispatchGroup) tolerates abandoning a reader that never reaches EOF.
        let readerFinished = DispatchSemaphore(value: 0)
        for (index, pipe) in pipes.enumerated() {
            let isError = separateErrorOutput && index == 1
            pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    readerFinished.signal()
                    return
                }
                lock.lock()
                if isError {
                    errorOutput.append(chunk.prefix(max(0, 65_536 - errorOutput.count)))
                } else {
                    let remaining = max(0, outputLimit - output.count)
                    output.append(chunk.prefix(remaining))
                    if chunk.count > remaining && stopOnOutputLimit {
                        outputExceeded = true
                        stopOwnedProcessLocked()
                    }
                }
                lock.unlock()
            }
        }
        let deadline = DispatchWorkItem { [self] in
            lock.lock()
            if !finished {
                timedOut = true
                stopOwnedProcessLocked()
            }
            lock.unlock()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        lock.lock()
        finished = true
        lock.unlock()
        deadline.cancel()
        let readDeadline = DispatchTime.now() + 2
        for _ in pipes where readerFinished.wait(timeout: readDeadline) == .timedOut {
            for pipe in pipes { pipe.fileHandleForReading.readabilityHandler = nil }
            break
        }
        for pipe in pipes { try? pipe.fileHandleForReading.close() }
        lock.lock()
        let text = String(decoding: output, as: UTF8.self)
        let errorText = String(decoding: errorOutput, as: UTF8.self)
        let didCancel = cancelled
        let didTimeOut = timedOut
        let didExceed = outputExceeded
        lock.unlock()
        if didCancel { throw CancellationError() }
        if didTimeOut { throw SystemDiagnosticError.timedOut(text) }
        if didExceed { throw SystemDiagnosticError.outputLimit(text) }
        let exitCode = process.terminationReason == .uncaughtSignal ? -process.terminationStatus : process.terminationStatus
        return Result(output: text, errorOutput: errorText, exitCode: exitCode)
    }

    private func stopOwnedProcessLocked() {
        guard !finished, process.isRunning, process.processIdentifier > 1 else { return }
        let pid = process.processIdentifier
        guard let grace = interruptGracePeriod else {
            // Fixed diagnostics have no child process tree; SIGKILL guarantees bounded cancellation.
            Darwin.kill(pid, SIGKILL)
            return
        }
        guard !stopRequested else { return }
        stopRequested = true
        Darwin.kill(pid, SIGINT)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) { [self] in
            lock.lock()
            if !finished, process.isRunning, process.processIdentifier == pid { Darwin.kill(pid, SIGKILL) }
            lock.unlock()
        }
    }
}
