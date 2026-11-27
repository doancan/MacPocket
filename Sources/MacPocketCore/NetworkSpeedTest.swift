import Foundation

/// Options for macOS's built-in `networkQuality` measurement (Apple's test servers, no third party).
public struct SpeedTestOptions: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Upload and download at once: closest to real load, and how Apple reports responsiveness.
        case parallel
        /// One after the other: each direction measured on an otherwise idle link.
        case sequential
        case downloadOnly
        case uploadOnly
    }

    public var mode: Mode = .parallel
    /// BSD interface name (en0, en1, pdp_ip0…); nil uses the route macOS picks.
    public var interface: String?
    /// Upper bound for the whole run, in seconds; nil lets the tool decide (~20 s).
    public var maximumSeconds: Int?
    /// Measure through iCloud Private Relay.
    public var usePrivateRelay = false

    public static let durationChoices: [Int?] = [nil, 10, 20, 30]
    public static let executable = "/usr/bin/networkQuality"

    public init() {}

    /// Interface names as the kernel reports them; anything else is refused before it reaches the process.
    public static func isValidInterface(_ name: String) -> Bool {
        name.range(of: #"^[a-z_]{1,12}[0-9]{1,3}$"#, options: .regularExpression) != nil
    }

    public var arguments: [String] {
        var arguments = ["-c"]
        switch mode {
        case .parallel: break
        case .sequential: arguments.append("-s")
        case .downloadOnly: arguments.append("-u") // -u: no upload test
        case .uploadOnly: arguments.append("-d") // -d: no download test
        }
        if let interface, Self.isValidInterface(interface) { arguments += ["-I", interface] }
        if let maximumSeconds { arguments += ["-M", String(min(max(maximumSeconds, 5), 120))] }
        if usePrivateRelay { arguments.append("-p") }
        return arguments
    }
}

public struct SpeedTestResult: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    /// Bits per second.
    public let downloadBitsPerSecond: Double?
    public let uploadBitsPerSecond: Double?
    /// Round trips per minute under load (higher is better).
    public let responsivenessRPM: Double?
    /// Idle round-trip time, milliseconds.
    public let baseRTTMilliseconds: Double?
    public let interface: String?
    public let endpoint: String?
    public let transferredBytes: Int64
    public let mode: SpeedTestOptions.Mode

    public init(date: Date, downloadBitsPerSecond: Double?, uploadBitsPerSecond: Double?, responsivenessRPM: Double?,
                baseRTTMilliseconds: Double?, interface: String?, endpoint: String?, transferredBytes: Int64, mode: SpeedTestOptions.Mode) {
        self.date = date
        self.downloadBitsPerSecond = downloadBitsPerSecond
        self.uploadBitsPerSecond = uploadBitsPerSecond
        self.responsivenessRPM = responsivenessRPM
        self.baseRTTMilliseconds = baseRTTMilliseconds
        self.interface = interface
        self.endpoint = endpoint
        self.transferredBytes = transferredBytes
        self.mode = mode
    }

    public enum Responsiveness: Equatable, Sendable {
        case low, medium, high
        public var title: String {
            switch self {
            case .low: String(localized: "Düşük")
            case .medium: String(localized: "Orta")
            case .high: String(localized: "Yüksek")
            }
        }
    }

    /// Rough bands for round trips per minute: video calls and games feel sluggish below 300, fine above
    /// 1000.
    public var responsiveness: Responsiveness? {
        guard let responsivenessRPM else { return nil }
        return responsivenessRPM < 300 ? .low : responsivenessRPM < 1000 ? .medium : .high
    }
}

public enum SpeedTestParseError: Error, LocalizedError, Equatable {
    case notJSON
    case reported(String)

    public var errorDescription: String? {
        switch self {
        case .notJSON: String(localized: "networkQuality beklenmeyen bir çıktı verdi.")
        case let .reported(message): String(localized: "Ölçüm tamamlanamadı: \(message)")
        }
    }
}

public enum SpeedTestParser {
    /// Parses `networkQuality -c` output. Values of zero mean that direction wasn't measured.
    public static func parse(_ data: Data, mode: SpeedTestOptions.Mode, now: Date = Date()) throws -> SpeedTestResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpeedTestParseError.notJSON }
        if let error = object["error_code"] ?? object["error"] {
            throw SpeedTestParseError.reported(String(describing: error))
        }
        func number(_ key: String) -> Double? {
            guard let value = (object[key] as? NSNumber)?.doubleValue, value.isFinite, value > 0 else { return nil }
            return value
        }
        let download = number("dl_throughput"), upload = number("ul_throughput")
        guard download != nil || upload != nil else { throw SpeedTestParseError.reported(String(localized: "hız ölçülemedi")) }
        let bytes = Int64(number("dl_bytes_transferred") ?? 0) + Int64(number("ul_bytes_transferred") ?? 0)
        return SpeedTestResult(date: now, downloadBitsPerSecond: download, uploadBitsPerSecond: upload,
                               responsivenessRPM: number("responsiveness"), baseRTTMilliseconds: number("base_rtt"),
                               interface: object["interface_name"] as? String, endpoint: object["test_endpoint"] as? String,
                               transferredBytes: bytes, mode: mode)
    }
}

/// Recent results, newest first, stored in UserDefaults.
public struct SpeedTestHistory: Codable, Equatable, Sendable {
    public private(set) var results: [SpeedTestResult] = []
    public static let limit = 30
    public static let storageKey = "MacPocket.speedTest.history"

    public init(results: [SpeedTestResult] = []) { self.results = Array(results.prefix(Self.limit)) }

    public mutating func add(_ result: SpeedTestResult) {
        results.insert(result, at: 0)
        if results.count > Self.limit { results.removeLast(results.count - Self.limit) }
    }

    public mutating func remove(_ id: SpeedTestResult.ID) { results.removeAll { $0.id == id } }
    public mutating func clear() { results = [] }

    public func best(_ value: KeyPath<SpeedTestResult, Double?>) -> Double? { results.compactMap { $0[keyPath: value] }.max() }

    public func median(_ value: KeyPath<SpeedTestResult, Double?>) -> Double? {
        let sorted = results.compactMap { $0[keyPath: value] }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    public static func load(from defaults: UserDefaults) -> SpeedTestHistory {
        guard let data = defaults.data(forKey: storageKey) else { return SpeedTestHistory() }
        return (try? JSONDecoder().decode(SpeedTestHistory.self, from: data)) ?? SpeedTestHistory()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum SpeedFormatter {
    /// "215 Mbps", "48,0 Mbps", "1,2 Gbps", "850 kbps" in the app's number style.
    public static func bitRate(_ bitsPerSecond: Double?) -> String {
        guard let bitsPerSecond else { return "—" }
        let (value, unit): (Double, String) = bitsPerSecond >= 1e9 ? (bitsPerSecond / 1e9, "Gbps")
            : bitsPerSecond >= 1e6 ? (bitsPerSecond / 1e6, "Mbps") : (bitsPerSecond / 1e3, "kbps")
        return MenuBarFormatter.number(value, fractionDigits: value < 100 ? 1 : 0) + " " + unit
    }
}

// MARK: - Running

public enum SpeedTestRunError: Error, LocalizedError, Equatable {
    case interfaceUnavailable(String)
    case timedOut
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case let .interfaceUnavailable(name): String(localized: "\(name) ağ arayüzü bu Mac’te yok veya bağlı değil.")
        case .timedOut: String(localized: "Ölçüm zaman aşımına uğradı.")
        case let .failed(status, message):
            message.isEmpty ? String(localized: "networkQuality başarısız oldu (\(status)).") : String(localized: "networkQuality başarısız oldu: \(message)")
        }
    }
}

/// Runs `/usr/bin/networkQuality` with argument-array options (no shell). Cancelling the task stops the tool;
/// a run longer than its limit plus 30 s is stopped and reported as timed out.
public enum SpeedTestRunner {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    public static func run(_ options: SpeedTestOptions) async throws -> SpeedTestResult {
        // networkQuality waits forever on an interface that doesn't exist, even with -M: refuse it up front.
        if let interface = options.interface, if_nametoindex(interface) == 0 {
            throw SpeedTestRunError.interfaceUnavailable(interface)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SpeedTestOptions.executable)
        process.arguments = options.arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let limit = options.maximumSeconds.map { Double($0) + 15 } ?? 90
        let timedOut = Flag()
        let watchdog = Task {
            try await Task.sleep(for: .seconds(limit))
            timedOut.set()
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }
        // Drain both pipes while the tool runs: its JSON (with latency samples) can exceed the pipe buffer,
        // and a writer blocked on a full pipe would never exit.
        let stdoutReader = PipeReader(output.fileHandleForReading)
        let stderrReader = PipeReader(errors.fileHandleForReading)
        return try await withTaskCancellationHandler {
            let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    // Nothing will write: close our ends so the readers see end of file.
                    try? output.fileHandleForWriting.close()
                    try? errors.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
            }
            let stdout = await stdoutReader.collect(limit: BoundedProcess.drainGrace)
            let stderr = await stderrReader.collect(limit: BoundedProcess.drainGrace)
            try Task.checkCancellation()
            if timedOut.isSet { throw SpeedTestRunError.timedOut }
            guard status == 0 else {
                let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw SpeedTestRunError.failed(status: status, message: String(message.prefix(300)))
            }
            return try SpeedTestParser.parse(stdout, mode: options.mode)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
