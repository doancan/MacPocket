import Darwin
import Foundation

/// A process identified by PID, birth time and owner rather than PID alone.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public let effectiveUserID: UInt32
    public let realUserID: UInt32
    public let executablePath: String
}

public struct ProcessEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let user: String
    public let state: String
    /// Percentage of one logical core over this monitor's sampling interval.
    /// A multithreaded process can exceed 100%. Check cpuSampleAvailable first.
    public let cpuPercent: Double
    public let cpuSampleAvailable: Bool
    public let residentBytes: UInt64
    public let memorySampleAvailable: Bool
    public let threadCount: Int32?
    public let parentPID: Int32
    /// Executable path only. Command-line arguments are not collected.
    public let command: String
    public let identity: ProcessIdentity
    public let canTerminate: Bool
}

public struct ProcessSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let processes: [ProcessEntry]
    public let listedProcessCount: Int
    /// Entries may become unreadable because they exited or access was denied.
    public let unreadableProcessCount: Int
}

public enum ProcessMonitorError: Error, LocalizedError, Equatable, Sendable {
    case enumerationFailed(Int32)
    case protectedProcess(Int32)
    case processNotObserved(Int32)
    case differentUser(Int32)
    case identityChanged(Int32)
    case identityUnavailable(Int32)
    case notRunning(Int32)
    case signalFailed(pid: Int32, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .enumerationFailed(let code):
            return String(localized: "Süreç listesi okunamadı (\(code)).")
        case .protectedProcess(let pid):
            return String(localized: "Korunan süreç sonlandırılamaz (PID \(pid)).")
        case .processNotObserved(let pid):
            return String(localized: "Süreç bu izleyicide seçilmeden sonlandırılamaz (PID \(pid)).")
        case .differentUser(let pid):
            return String(localized: "Başka kullanıcıya ait süreç sonlandırılamaz (PID \(pid)).")
        case .identityChanged(let pid):
            return String(localized: "Süreç kimliği değişti; listeyi yenileyip yeniden seçin (PID \(pid)).")
        case .identityUnavailable(let pid):
            return String(localized: "Süreç kimliği doğrulanamadı (PID \(pid)).")
        case .notRunning(let pid):
            return String(localized: "Süreç artık çalışmıyor (PID \(pid)).")
        case .signalFailed(let pid, let code):
            return String(localized: "Sonlandırma isteği gönderilemedi (PID \(pid), hata \(code)).")
        }
    }
}

/// Read-only libproc sampling, with explicit user-owned process termination.
///
/// `terminate(entry:)` is the selection-preserving API for a UI. `terminate(pid:)`
/// uses the identity in this actor's latest snapshot. Neither launches a shell.
/// Darwin's PID-based kill call cannot atomically bind a signal to a start time:
/// immediate identity revalidation narrows, but cannot eliminate, that race.
public actor ProcessMonitor {
    private struct CPUObservation {
        let identity: ProcessIdentity
        let counterTicks: UInt64
        let sampledAtTicks: UInt64
    }

    private var previousCPU: [Int32: CPUObservation] = [:]
    private var observed: [Int32: ProcessEntry] = [:]
    private var userNames: [UInt32: String] = [:]
    private let protectedPIDs: Set<Int32>

    public init() {
        var ancestors: Set<Int32> = [0, 1, getpid()]
        var next = getppid()
        while next > 1 && ancestors.insert(next).inserted {
            guard let info = Self.readBSD(pid: next) else { break }
            next = Int32(bitPattern: info.pbi_ppid)
        }
        protectedPIDs = ancestors
    }

    public func snapshot() throws -> ProcessSnapshot {
        let pids = try Self.listPIDs()
        var entries: [ProcessEntry] = []
        var freshCPU: [Int32: CPUObservation] = [:]
        var unreadableCount = 0
        entries.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            var task = proc_taskallinfo()
            let taskSize = Int32(MemoryLayout<proc_taskallinfo>.size)
            let bytes = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &task, taskSize)
            let hasTask = bytes == taskSize
            guard let bsd = hasTask ? task.pbsd : Self.readBSD(pid: pid) else {
                unreadableCount += 1
                continue
            }
            let sampledAt = mach_absolute_time()
            let executable = Self.executablePath(pid: pid)
            let identity = Self.identity(pid: pid, info: bsd, executablePath: executable)
            let rawName = Self.name(info: bsd)
            let name = rawName.isEmpty
                ? (executable.isEmpty ? "PID \(pid)" : URL(fileURLWithPath: executable).lastPathComponent)
                : rawName

            var cpuPercent = 0.0
            var cpuAvailable = false
            if hasTask {
                let sum = task.ptinfo.pti_total_user.addingReportingOverflow(task.ptinfo.pti_total_system)
                if !sum.overflow {
                    if let previous = previousCPU[pid], previous.identity == identity,
                       let measured = Self.cpuPercentage(
                        previousCounter: previous.counterTicks,
                        currentCounter: sum.partialValue,
                        previousClock: previous.sampledAtTicks,
                        currentClock: sampledAt
                       ) {
                        cpuPercent = measured
                        cpuAvailable = true
                    }
                    freshCPU[pid] = CPUObservation(
                        identity: identity, counterTicks: sum.partialValue, sampledAtTicks: sampledAt
                    )
                }
            }

            let eligible = !protectedPIDs.contains(pid)
                && bsd.pbi_uid == getuid() && bsd.pbi_ruid == getuid()
                && (bsd.pbi_flags & UInt32(PROC_FLAG_SYSTEM)) == 0
                && bsd.pbi_status != UInt32(SZOMB)
                && !executable.isEmpty
                && !Self.isSessionCritical(executable)
            entries.append(ProcessEntry(
                pid: pid, name: name, user: userName(uid: bsd.pbi_uid),
                state: Self.stateName(bsd.pbi_status),
                cpuPercent: cpuPercent, cpuSampleAvailable: cpuAvailable,
                residentBytes: hasTask ? task.ptinfo.pti_resident_size : 0,
                memorySampleAvailable: hasTask,
                threadCount: hasTask ? task.ptinfo.pti_threadnum : nil,
                parentPID: Int32(bitPattern: bsd.pbi_ppid),
                command: executable, identity: identity, canTerminate: eligible
            ))
        }

        previousCPU = freshCPU
        observed = Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0) })
        return ProcessSnapshot(
            capturedAt: Date(), processes: entries.sorted { $0.pid < $1.pid },
            listedProcessCount: pids.count, unreadableProcessCount: unreadableCount
        )
    }

    /// Sends SIGTERM by default. Force termination requires `force: true`.
    public func terminate(pid: Int32, force: Bool = false) throws {
        guard !protectedPIDs.contains(pid), pid > 1 else {
            throw ProcessMonitorError.protectedProcess(pid)
        }
        guard let entry = observed[pid] else {
            throw ProcessMonitorError.processNotObserved(pid)
        }
        try terminate(entry: entry, force: force)
    }

    /// Revalidates the selected process identity, ownership and executable.
    public func terminate(entry: ProcessEntry, force: Bool = false) throws {
        let pid = entry.pid
        guard pid > 1 && !protectedPIDs.contains(pid) else {
            throw ProcessMonitorError.protectedProcess(pid)
        }
        guard let last = observed[pid] else {
            throw ProcessMonitorError.processNotObserved(pid)
        }
        guard last.identity == entry.identity else {
            throw ProcessMonitorError.identityChanged(pid)
        }
        guard entry.identity.effectiveUserID == getuid(), entry.identity.realUserID == getuid() else {
            throw ProcessMonitorError.differentUser(pid)
        }
        guard let current = Self.readBSD(pid: pid) else {
            throw ProcessMonitorError.notRunning(pid)
        }
        guard current.pbi_uid == getuid(), current.pbi_ruid == getuid() else {
            throw ProcessMonitorError.differentUser(pid)
        }
        guard (current.pbi_flags & UInt32(PROC_FLAG_SYSTEM)) == 0,
              current.pbi_status != UInt32(SZOMB) else {
            throw ProcessMonitorError.protectedProcess(pid)
        }
        let executable = Self.executablePath(pid: pid)
        guard !executable.isEmpty else {
            throw ProcessMonitorError.identityUnavailable(pid)
        }
        guard !Self.isSessionCritical(executable) else {
            throw ProcessMonitorError.protectedProcess(pid)
        }
        guard Self.identity(pid: pid, info: current, executablePath: executable) == entry.identity else {
            throw ProcessMonitorError.identityChanged(pid)
        }
        guard kill(pid, force ? SIGKILL : SIGTERM) == 0 else {
            throw ProcessMonitorError.signalFailed(pid: pid, code: errno)
        }
        // A process may ignore SIGTERM; keep it observed so "force" stays possible until the
        // next snapshot shows it gone. SIGKILL cannot be ignored.
        if force {
            observed.removeValue(forKey: pid)
            previousCPU.removeValue(forKey: pid)
        }
    }

    /// User-owned processes whose termination logs the user out or breaks the session.
    /// OS daemons and agents are never a cleanup target. Apps in /System/Applications (Mail, Music…)
    /// and relaunching shells like Finder/Dock stay terminable, as in Activity Monitor.
    static func isSessionCritical(_ executable: String) -> Bool {
        let systemRoots = ["/System/Library/PrivateFrameworks/", "/System/Library/Frameworks/",
                           "/usr/libexec/", "/usr/sbin/", "/sbin/"]
        if systemRoots.contains(where: executable.hasPrefix) { return true }
        let critical: Set<String> = ["loginwindow", "launchd", "WindowServer", "SystemUIServer", "ControlCenter",
                                     "cfprefsd", "distnoted", "UserEventAgent", "secd", "trustd"]
        return critical.contains(URL(fileURLWithPath: executable).lastPathComponent)
    }

    // Task CPU counters and mach_absolute_time both use native Mach ticks.
    // Taking their ratio avoids treating Apple Silicon ticks as nanoseconds.
    static func cpuPercentage(
        previousCounter: UInt64, currentCounter: UInt64,
        previousClock: UInt64, currentClock: UInt64
    ) -> Double? {
        guard currentClock > previousClock, currentCounter >= previousCounter else { return nil }
        let value = Double(currentCounter - previousCounter)
            / Double(currentClock - previousClock) * 100
        return value.isFinite ? value : nil
    }

    private static func listPIDs() throws -> [Int32] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { throw ProcessMonitorError.enumerationFailed(errno) }
        var capacity = max(1024, Int(estimated) + 256)
        for _ in 0..<4 {
            var buffer = [Int32](repeating: 0, count: capacity)
            let count = buffer.withUnsafeMutableBytes {
                proc_listallpids($0.baseAddress, Int32($0.count))
            }
            guard count >= 0 else { throw ProcessMonitorError.enumerationFailed(errno) }
            if Int(count) < capacity {
                return Array(Set(buffer.prefix(Int(count)).filter { $0 > 0 })).sorted()
            }
            capacity *= 2
        }
        throw ProcessMonitorError.enumerationFailed(EOVERFLOW)
    }

    private static func readBSD(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func executablePath(pid: Int32) -> String {
        // PROC_PIDPATHINFO_MAXSIZE is (4 * MAXPATHLEN), a C macro Swift cannot import.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = UInt32(buffer.count)
        guard proc_pidpath(pid, &buffer, size) > 0 else { return "" }
        return buffer.withUnsafeBytes { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func identity(pid: Int32, info: proc_bsdinfo, executablePath: String) -> ProcessIdentity {
        ProcessIdentity(
            pid: pid, startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec,
            effectiveUserID: info.pbi_uid, realUserID: info.pbi_ruid,
            executablePath: executablePath
        )
    }

    private static func name(info: proc_bsdinfo) -> String {
        var copy = info
        let preferred = withUnsafeBytes(of: &copy.pbi_name) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return preferred.isEmpty ? withUnsafeBytes(of: &copy.pbi_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        } : preferred
    }

    private static func stateName(_ state: UInt32) -> String {
        switch state {
        case UInt32(SIDL): return "starting"
        case UInt32(SRUN): return "running"
        case UInt32(SSLEEP): return "sleeping"
        case UInt32(SSTOP): return "stopped"
        case UInt32(SZOMB): return "zombie"
        default: return "unknown"
        }
    }

    private func userName(uid: UInt32) -> String {
        if let name = userNames[uid] { return name }
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        let count = buffer.count
        let status = getpwuid_r(uid, &record, &buffer, count, &result)
        let name = status == 0 && result != nil
            ? String(cString: record.pw_name) : String(uid)
        userNames[uid] = name
        return name
    }
}
