import Foundation

/// Runs a tool with a time limit, off the main thread. Output is drained while it runs (a full pipe would
/// block the tool forever); on timeout or cancellation the tool and the processes it started get SIGTERM,
/// then SIGKILL after a grace period if they ignore it.
public enum BoundedProcess {
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
        public let errorOutput: String
        public init(status: Int32, output: String, errorOutput: String) {
            self.status = status
            self.output = output
            self.errorOutput = errorOutput
        }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case timedOut
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .timedOut: String(localized: "Süre sınırı aşıldı; işlem durduruldu.")
            case .cancelled: String(localized: "İşlem durduruldu.")
            }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    public static let killGrace: TimeInterval = 2
    /// How long to wait for the output pipes to close once the process has exited.
    static let drainGrace: TimeInterval = 1

    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let timedOut = Flag(), cancelled = Flag()
        let outputReader = PipeReader(output.fileHandleForReading)
        let errorReader = PipeReader(errors.fileHandleForReading)
        let watchdog = Task.detached {
            try await Task.sleep(for: .seconds(timeout))
            timedOut.set()
            stop(process)
        }
        defer { watchdog.cancel() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    try? output.fileHandleForWriting.close()
                    try? errors.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
                // Cancelled before the process existed: the handler below ran too early to stop it.
                if cancelled.isSet { Task.detached { stop(process) } }
            }
        } onCancel: {
            cancelled.set()
            Task.detached { stop(process) }
        }
        let stdout = await outputReader.collect(limit: drainGrace), stderr = await errorReader.collect(limit: drainGrace)
        if cancelled.isSet { throw Failure.cancelled }
        if timedOut.isSet { throw Failure.timedOut }
        return Result(status: status, output: String(decoding: stdout, as: UTF8.self), errorOutput: String(decoding: stderr, as: UTF8.self))
    }

    /// SIGTERM to the process and its direct children, SIGKILL after the grace period for whatever is left.
    /// The grace period is a timer, not a sleep, so no thread waits on it and it outlives a cancelled watchdog.
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard pid > 1 else { return }
        let children = childPIDs(of: pid)
        for child in children { kill(child, SIGTERM) }
        kill(pid, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) {
            for child in children where kill(child, 0) == 0 { kill(child, SIGKILL) }
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        let count = proc_listchildpids(pid, nil, 0)
        guard count > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(count) * 2)
        let found = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        return Array(buffer.prefix(Int(max(0, found)))).filter { $0 > 1 }
    }
}

/// Drains a pipe on a dispatch thread. A read parks until every writer closes its end, and parking the
/// cooperative pool (one thread per core) would starve the watchdogs that end the processes. What was read is
/// kept, so the caller can stop waiting for end of file when a leftover child still holds the pipe open.
final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let finished = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.withLock { buffer.append(chunk) }
            }
            finished.signal()
        }
    }

    /// Waits for end of file, but at most `limit`.
    func collect(limit: TimeInterval) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                _ = finished.wait(timeout: .now() + limit)
                continuation.resume(returning: lock.withLock { buffer })
            }
        }
    }
}
