#if DEBUG
import AppKit
import Darwin
import MacPocketCore

/// Real child processes and production leases, with a file backend instead of WindowServer.
/// This entry precedes application state and never starts modules or global input capture.
@MainActor enum SwitcherNativeKeyRuntimeAudit {
    static func runIfRequested(_ arguments: [String]) {
        guard arguments.count == 2 else { return }
        if arguments[0] == "--audit-native-key-owner-crash" {
            let file = URL(fileURLWithPath: arguments[1])
            guard SwitcherNativeKeyFixture.valid(file),let executable = Bundle.main.executableURL else { exit(65) }
            do {
                let lease = try SwitcherNativeKeyLease.fixture(executable: executable,file: file,timeout: 1)
                try Data("armed".utf8).write(to: file.deletingLastPathComponent().appendingPathComponent("owner-ready"))
                // Intentionally bypass all Swift/Foundation cleanup in this owned fixture process.
                withExtendedLifetime(lease) { _exit(0) }
            } catch { exit(70) }
        }
        guard arguments[0] == "--audit-switcher-native-keys" else { return }
        let report = URL(fileURLWithPath: arguments[1])
        Task { @MainActor in
            var checks: [String:Bool] = [:]
            let before = SwitcherNativeKeyGuard.currentState(),secure = SecureKeyboardInputStatus.read()
            var failure: String?
            do { try await run(checks: &checks) } catch { failure = String(describing: error) }
            checks["systemKeysUnchanged"] = before != nil && before == SwitcherNativeKeyGuard.currentState()
            let passed = failure == nil && !checks.isEmpty && checks.values.allSatisfy { $0 }
            var result: [String:Any] = ["passed": passed,"checks": checks,"backend": "UUID-owned-file-fixture",
                "productionLeaseAndPipeProtocol": true,"globalSettersExercised": false,"physicalKeyboardVerified": false,
                "secureInputEnabled": secure.enabled,"secureInputOwnerPID": secure.processID ?? 0]
            if let failure { result["error"] = failure }
            do {
                let data = try JSONSerialization.data(withJSONObject: result,options: [.sortedKeys,.prettyPrinted])
                try data.write(to: report,options: .atomic)
                exit(passed ? 0 : 1)
            } catch { exit(74) }
        }
        RunLoop.main.run()
        exit(70)
    }

    private static func file(_ original: [String:Bool]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket.NativeKeyAudit")
            .appendingPathComponent(UUID().uuidString,isDirectory: true)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("state.json")
        try JSONSerialization.data(withJSONObject: original).write(to: file,options: .atomic)
        return file
    }
    private static func state(_ file: URL) -> [String:Bool]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String:Bool]
    }
    private static func until(_ predicate: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(),ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        return predicate()
    }
    private static func run(checks: inout [String:Bool]) async throws {
        guard let executable = Bundle.main.executableURL else { throw SwitcherNativeKeyError.unavailable }
        for mask in 0...3 {
            let original = ["1": mask & 1 != 0,"2": mask & 2 != 0],file = try file(original)
            let lease = try SwitcherNativeKeyLease.fixture(executable: executable,file: file)
            checks["acquire-\(mask)"] = lease.isActive && state(file) == ["1":false,"2":false]
            do {
                _ = try SwitcherNativeKeyLease.fixture(executable: executable,file: file)
                checks["overlap-rejected-\(mask)"] = false
            } catch { checks["overlap-rejected-\(mask)"] = true }
            checks["stop-\(mask)"] = lease.stop() && state(file) == original
            checks["exited-\(mask)"] = try await until { !lease.isRunning }
        }
        let original = ["1":true,"2":false],disabled = ["1":false,"2":false]
        let heartbeatFile = try file(original)
        let heartbeat = try SwitcherNativeKeyLease.fixture(executable: executable,file: heartbeatFile,timeout: 0.35)
        var alive = true
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(100))
            alive = heartbeat.pulse() && state(heartbeatFile) == disabled && alive
        }
        checks["heartbeat-retains-past-timeout"] = alive
        checks["heartbeat-stop"] = heartbeat.stop() && state(heartbeatFile) == original
        // Reacquire immediately after Q acknowledgement, before a late old termination callback.
        let replacement = try SwitcherNativeKeyLease.fixture(executable: executable,file: heartbeatFile,timeout: 1)
        try await Task.sleep(for: .milliseconds(100))
        checks["late-callback-cannot-restore-new-lease"] = replacement.isActive && state(heartbeatFile) == disabled
        checks["replacement-stopped"] = replacement.stop() && state(heartbeatFile) == original
        _ = try await until { !replacement.isRunning }

        let timeoutFile = try file(original)
        let timeout = try SwitcherNativeKeyLease.fixture(executable: executable,file: timeoutFile,timeout: 0.25)
        // Stall the owner thread: the independent child must recover without a UI callback.
        usleep(600_000)
        checks["stalled-owner-restored"] = state(timeoutFile) == original
        checks["timeout-exited"] = try await until { !timeout.isRunning }
        _ = timeout.stop()

        let killedFile = try file(original)
        let killed = try SwitcherNativeKeyLease.fixture(executable: executable,file: killedFile,timeout: 1)
        killed.killFixtureChildForAudit()
        checks["killed-child-parent-restores"] = try await until { !killed.isRunning && state(killedFile) == original }
        _ = killed.stop()

        let droppedFile = try file(original)
        var dropped: SwitcherNativeKeyLease? = try SwitcherNativeKeyLease.fixture(executable: executable,file: droppedFile,timeout: 1)
        let handles = dropped?.fixturePipeHandlesForAudit
        checks["drop-fixture-armed"] = dropped?.isActive == true
        dropped = nil
        var inputClosed = false,outputClosed = false
        if let handles {
            do { try handles.input.write(contentsOf: Data()) } catch { inputClosed = true }
            do { _ = try handles.output.read(upToCount: 0) } catch { outputClosed = true }
        }
        checks["owner-release-closes-both-parent-pipe-descriptors"] = inputClosed && outputClosed
        checks["owner-release-closes-pipe-and-restores"] = try await until { state(droppedFile) == original }
        // The registry retains a Process solely to prevent a still-exiting old guardian overlap.
        try await Task.sleep(for: .milliseconds(100))

        let crashedFile = try file(original),owner = Process()
        owner.executableURL = executable
        owner.arguments = ["--audit-native-key-owner-crash",crashedFile.path]
        owner.standardOutput = FileHandle.nullDevice
        owner.standardError = FileHandle.nullDevice
        try owner.run()
        checks["crashed-owner-exits"] = try await until { !owner.isRunning }
        checks["crashed-owner-was-armed"] = !owner.isRunning && owner.terminationStatus == 0 && FileManager.default.fileExists(atPath: crashedFile.deletingLastPathComponent().appendingPathComponent("owner-ready").path)
        checks["crashed-owner-child-restores-without-parent-cleanup"] = try await until { state(crashedFile) == original }

        let failedFile = try file(original)
        let failed = try SwitcherNativeKeyLease.fixture(executable: executable,file: failedFile,timeout: 0.25)
        let denial = failedFile.deletingLastPathComponent().appendingPathComponent("deny-restoration")
        try Data().write(to: denial)
        _ = try await until { !failed.isRunning }
        checks["failed-restoration-not-reported-as-stopped"] = !failed.stop() && state(failedFile) == disabled
        do {
            _ = try SwitcherNativeKeyLease.fixture(executable: executable,file: failedFile)
            checks["failed-restoration-blocks-new-owner"] = false
        } catch { checks["failed-restoration-blocks-new-owner"] = true }
        try FileManager.default.removeItem(at: denial)
        checks["restoration-can-recover-after-transient-failure"] = failed.stop() && state(failedFile) == original
        let recovered = try SwitcherNativeKeyLease.fixture(executable: executable,file: failedFile)
        checks["recovered-state-allows-new-owner"] = recovered.isActive && recovered.stop() && state(failedFile) == original
        _ = try await until { !recovered.isRunning }
    }
}
#endif
