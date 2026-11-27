import Foundation

/// A booted iOS simulator ignores the quit request at power off, so macOS waits for its service timeout
/// (about 33 s) before killing it. Shutting the simulators down first lets the Mac power off without that
/// wait.
public enum SimulatorShutdown {
    public static let defaultsKey = "MacPocket.systemData.shutdownSimulatorsAtPowerOff"
    public static let defaultEnabled = true

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }

    /// Number of booted simulators, or nil when `simctl` is not available. Runs synchronously with a
    /// deadline.
    public static func bootedCount(timeout: TimeInterval = 5) -> Int? {
        guard let output = runSynchronously(["list", "devices", "booted", "-j"], timeout: timeout) else { return nil }
        return SystemDataParsers.simulatorDevices(Data(output.utf8)).filter(\.isBooted).count
    }

    /// Shuts every booted simulator down and returns once they are off (or the deadline passed). Synchronous
    /// on purpose: it runs while the system is already powering off. Returns the number that was booted
    /// before.
    @discardableResult
    public static func shutdownAll(timeout: TimeInterval = 20) -> Int {
        guard let count = bootedCount(), count > 0 else { return 0 }
        _ = runSynchronously(["shutdown", "all"], timeout: timeout)
        return count
    }

    /// Standard output goes to a temporary file, so no pipe can fill up while this thread waits.
    private static func runSynchronously(_ arguments: [String], timeout: TimeInterval) -> String? {
        let executable = "/usr/bin/xcrun"
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let capture = FileManager.default.temporaryDirectory.appending(path: "simctl-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: capture.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: capture) else { return nil }
        defer { try? sink.close(); try? FileManager.default.removeItem(at: capture) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["simctl"] + arguments
        process.standardOutput = sink
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: capture) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
