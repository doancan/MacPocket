import Darwin
import Foundation

/// Cumulative per-process counters from `proc_pid_rusage(RUSAGE_INFO_V6)`.
public struct ProcessEnergyCounters: Equatable, Sendable {
    public let pid: Int32
    /// Process start time (mach absolute) distinguishes a reused PID.
    public let startAbsoluteTime: UInt64
    public let energyNanojoules: UInt64
    public let billedEnergy: UInt64
    /// User + system CPU time in nanoseconds.
    public let cpuNanoseconds: UInt64
    public let wakeups: UInt64

    public init(pid: Int32, startAbsoluteTime: UInt64, energyNanojoules: UInt64, billedEnergy: UInt64,
                cpuNanoseconds: UInt64, wakeups: UInt64) {
        self.pid = pid; self.startAbsoluteTime = startAbsoluteTime; self.energyNanojoules = energyNanojoules
        self.billedEnergy = billedEnergy; self.cpuNanoseconds = cpuNanoseconds; self.wakeups = wakeups
    }
}

public struct ProcessEnergyUsage: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let executablePath: String
    /// Average power over the interval in milliwatts (from `ri_energy_nj`).
    public let milliwatts: Double
    /// Percentage of one core.
    public let cpuPercent: Double
    public let wakeupsPerSecond: Double
    /// Energy consumed during the interval, in joules.
    public let joules: Double
}

public struct ProcessEnergySample: Equatable, Sendable {
    public let capturedAt: Date
    public let interval: TimeInterval
    public let processes: [ProcessEnergyUsage]
    public let readableCount: Int
    public let unreadableCount: Int
    public var totalMilliwatts: Double { processes.reduce(0) { $0 + $1.milliwatts } }
}

public enum ProcessEnergyMath {
    /// Delta between two cumulative samples of the same process. Returns nil for a reused PID,
    /// a non-positive interval or counters that went backwards.
    public static func usage(previous: ProcessEnergyCounters, current: ProcessEnergyCounters,
                             interval: TimeInterval, name: String, path: String) -> ProcessEnergyUsage? {
        guard interval > 0, previous.pid == current.pid,
              previous.startAbsoluteTime == current.startAbsoluteTime,
              current.energyNanojoules >= previous.energyNanojoules,
              current.cpuNanoseconds >= previous.cpuNanoseconds,
              current.wakeups >= previous.wakeups else { return nil }
        let joules = Double(current.energyNanojoules - previous.energyNanojoules) / 1_000_000_000
        let cpuSeconds = Double(current.cpuNanoseconds - previous.cpuNanoseconds) / 1_000_000_000
        return ProcessEnergyUsage(pid: current.pid, name: name, executablePath: path,
                                  milliwatts: joules / interval * 1000,
                                  cpuPercent: cpuSeconds / interval * 100,
                                  wakeupsPerSecond: Double(current.wakeups - previous.wakeups) / interval,
                                  joules: joules)
    }

    /// Converts mach absolute units to nanoseconds without overflowing for large values.
    public static func nanoseconds(fromAbsolute value: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        guard denom > 0 else { return value }
        if numer == denom { return value }
        let (high, low) = value.multipliedFullWidth(by: UInt64(numer))
        guard high < UInt64(denom) else { return UInt64.max }
        return UInt64(denom).dividingFullWidth((high, low)).quotient
    }
}

/// Samples energy for every process readable by the current user. Root-owned processes return EPERM
/// and are counted as unreadable. Keep one instance per visible page; drop it when the page closes.
public actor ProcessEnergySampler {
    private var previous: [Int32: ProcessEnergyCounters] = [:]
    private var previousAt: UInt64 = 0
    private let timebase: mach_timebase_info_data_t

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = info
    }

    /// The first call primes counters and returns an empty list; later calls report the interval since.
    public func sample(limit: Int = 40) -> ProcessEnergySample {
        let now = mach_absolute_time()
        let interval = previousAt == 0 ? 0
            : Double(ProcessEnergyMath.nanoseconds(fromAbsolute: now &- previousAt, numer: timebase.numer,
                                                   denom: timebase.denom)) / 1_000_000_000
        var fresh: [Int32: ProcessEnergyCounters] = [:]
        var usages: [ProcessEnergyUsage] = []
        var unreadable = 0
        for pid in Self.listPIDs() where pid > 0 {
            guard let counters = counters(pid: pid) else { unreadable += 1; continue }
            fresh[pid] = counters
            guard let old = previous[pid] else { continue }
            let path = Self.path(pid: pid)
            let name = Self.name(pid: pid, path: path)
            if let usage = ProcessEnergyMath.usage(previous: old, current: counters, interval: interval, name: name, path: path),
               usage.milliwatts > 0 || usage.cpuPercent > 0 {
                usages.append(usage)
            }
        }
        previous = fresh
        previousAt = now
        usages.sort { $0.milliwatts == $1.milliwatts ? $0.cpuPercent > $1.cpuPercent : $0.milliwatts > $1.milliwatts }
        return ProcessEnergySample(capturedAt: Date(), interval: interval, processes: Array(usages.prefix(limit)),
                                   readableCount: fresh.count, unreadableCount: unreadable)
    }

    private func counters(pid: Int32) -> ProcessEnergyCounters? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0 else { return nil }
        let cpu = ProcessEnergyMath.nanoseconds(fromAbsolute: info.ri_user_time &+ info.ri_system_time,
                                                numer: timebase.numer, denom: timebase.denom)
        return ProcessEnergyCounters(pid: pid, startAbsoluteTime: info.ri_proc_start_abstime,
                                     energyNanojoules: info.ri_energy_nj, billedEnergy: info.ri_billed_energy,
                                     cpuNanoseconds: cpu, wakeups: info.ri_pkg_idle_wkups &+ info.ri_interrupt_wkups)
    }

    private static func listPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private static func path(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func name(pid: Int32, path: String) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return path.isEmpty ? "PID \(pid)" : URL(fileURLWithPath: path).lastPathComponent
    }
}
