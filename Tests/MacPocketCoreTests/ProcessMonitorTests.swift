import Darwin
import Foundation
import XCTest
@testable import MacPocketCore

final class ProcessMonitorTests: XCTestCase, @unchecked Sendable {
    func testCPUSamplingUsesIntervalsAndPermitsMultipleCores() {
        XCTAssertEqual(ProcessMonitor.cpuPercentage(
            previousCounter: 100, currentCounter: 600,
            previousClock: 1000, currentClock: 1250
        ), 200)
        XCTAssertNil(ProcessMonitor.cpuPercentage(
            previousCounter: 100, currentCounter: 99,
            previousClock: 1000, currentClock: 1250
        ))
        XCTAssertNil(ProcessMonitor.cpuPercentage(
            previousCounter: 100, currentCounter: 110,
            previousClock: 1000, currentClock: 1000
        ))
    }

    func testFirstSnapshotMarksCPUUnavailableAndSecondMeasures() async throws {
        let monitor = ProcessMonitor()
        let first = try await monitor.snapshot()
        let own = try XCTUnwrap(first.processes.first { $0.pid == getpid() })
        XCTAssertFalse(own.cpuSampleAvailable)
        XCTAssertTrue(own.memorySampleAvailable)
        XCTAssertGreaterThan(own.residentBytes, 0)
        XCTAssertFalse(own.canTerminate)
        XCTAssertEqual(own.identity.effectiveUserID, getuid())
        XCTAssertFalse(own.command.isEmpty)
        try await Task.sleep(for: .milliseconds(30))
        let second = try await monitor.snapshot()
        let measured = try XCTUnwrap(second.processes.first { $0.pid == getpid() })
        XCTAssertTrue(measured.cpuSampleAvailable)
        XCTAssertGreaterThanOrEqual(measured.cpuPercent, 0)
        XCTAssertEqual(own.identity, measured.identity)
    }

    func testProtectedPIDsAreRejectedBeforeAnySignal() async throws {
        let monitor = ProcessMonitor()
        for pid: Int32 in [-1, 0, 1, getpid(), getppid()] {
            do {
                try await monitor.terminate(pid: pid)
                XCTFail("Protected PID \(pid) was accepted")
            } catch let error as ProcessMonitorError {
                XCTAssertEqual(error, .protectedProcess(pid))
            }
        }
    }

    func testTerminationRequiresAnObservedProcess() async throws {
        let child = try startSleep()
        defer { cleanUp(child) }
        do {
            try await ProcessMonitor().terminate(pid: child.processIdentifier)
            XCTFail("Unobserved PID was accepted")
        } catch let error as ProcessMonitorError {
            XCTAssertEqual(error, .processNotObserved(child.processIdentifier))
        }
        XCTAssertTrue(try child.isRunning)
    }

    func testGracefulTerminationOnlyOfOwnedFixture() async throws {
        let child = try startSleep()
        defer { cleanUp(child) }
        let monitor = ProcessMonitor()
        let snapshot = try await monitor.snapshot()
        let entry = try XCTUnwrap(snapshot.processes.first { $0.pid == child.processIdentifier })
        XCTAssertTrue(entry.canTerminate)
        try await monitor.terminate(entry: entry)
        let status = try await waitForExit(child)
        XCTAssertEqual(status & 0x7f, SIGTERM)
    }

    func testForceTerminationOnlyOfOwnedFixture() async throws {
        let child = try startSleep()
        defer { cleanUp(child) }
        let monitor = ProcessMonitor()
        _ = try await monitor.snapshot()
        try await monitor.terminate(pid: child.processIdentifier, force: true)
        let status = try await waitForExit(child)
        XCTAssertEqual(status & 0x7f, SIGKILL)
    }

    func testStaleSelectionIdentityIsRejected() async throws {
        let child = try startSleep()
        defer { cleanUp(child) }
        let monitor = ProcessMonitor()
        let snapshot = try await monitor.snapshot()
        let entry = try XCTUnwrap(snapshot.processes.first { $0.pid == child.processIdentifier })
        let wrongIdentity = ProcessIdentity(
            pid: entry.pid, startSeconds: entry.identity.startSeconds + 1,
            startMicroseconds: entry.identity.startMicroseconds,
            effectiveUserID: entry.identity.effectiveUserID,
            realUserID: entry.identity.realUserID,
            executablePath: entry.identity.executablePath
        )
        let stale = ProcessEntry(
            pid: entry.pid, name: entry.name, user: entry.user, state: entry.state,
            cpuPercent: entry.cpuPercent, cpuSampleAvailable: entry.cpuSampleAvailable,
            residentBytes: entry.residentBytes, memorySampleAvailable: entry.memorySampleAvailable,
            threadCount: entry.threadCount, parentPID: entry.parentPID, command: entry.command,
            identity: wrongIdentity, canTerminate: entry.canTerminate
        )
        do {
            try await monitor.terminate(entry: stale)
            XCTFail("Stale selection was accepted")
        } catch let error as ProcessMonitorError {
            XCTAssertEqual(error, .identityChanged(entry.pid))
        }
        XCTAssertTrue(try child.isRunning)
    }

    private func startSleep() throws -> OwnedSleep {
        try OwnedSleep()
    }

    private func waitForExit(_ process: OwnedSleep) async throws -> Int32 {
        for _ in 0..<100 {
            if let status = try process.pollExit() { return status }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw FixtureError.exitDeadline
    }

    private func cleanUp(_ process: OwnedSleep) {
        do {
            try process.cleanUp()
        } catch {
            XCTFail("Owned fixture cleanup failed: \(error)")
        }
    }

    private enum FixtureError: Error {
        case exitDeadline
        case cleanupDeadline
    }

    /// Foundation's Process.waitUntilExit can enter an unbounded run-loop wait
    /// from an XCTest cooperative executor. This fixture instead owns spawning
    /// and reaping itself; every waitpid call is nonblocking and deadline bound.
    private final class OwnedSleep: @unchecked Sendable {
        let processIdentifier: Int32
        private var exitStatus: Int32?
        private let lock = NSLock()

        init() throws {
            var pid: pid_t = 0
            var attributes: posix_spawnattr_t?
            let initialization = posix_spawnattr_init(&attributes)
            guard initialization == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: initialization) ?? .EIO)
            }
            defer { posix_spawnattr_destroy(&attributes) }
            // A test runner can block or ignore SIGTERM. Establish the fixture's
            // own signal contract instead of inheriting runner-specific state.
            var defaults = sigset_t()
            var mask = sigset_t()
            sigemptyset(&defaults)
            sigemptyset(&mask)
            for signal in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] { sigaddset(&defaults, signal) }
            for result in [
                posix_spawnattr_setsigdefault(&attributes, &defaults),
                posix_spawnattr_setsigmask(&attributes, &mask),
                posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)),
            ] where result != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
            }
            let executable = strdup("/bin/sleep")!
            let duration = strdup("30")!
            defer {
                free(executable)
                free(duration)
            }
            var arguments: [UnsafeMutablePointer<CChar>?] = [executable, duration, nil]
            var environment: [UnsafeMutablePointer<CChar>?] = [nil]
            let result = arguments.withUnsafeMutableBufferPointer { argv in
                environment.withUnsafeMutableBufferPointer { envp in
                    posix_spawn(&pid, "/bin/sleep", nil, &attributes, argv.baseAddress!, envp.baseAddress!)
                }
            }
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
            }
            processIdentifier = pid
        }

        var isRunning: Bool {
            get throws { try pollExit() == nil }
        }

        func pollExit() throws -> Int32? {
            try lock.withLock {
                if let exitStatus { return exitStatus }
                var status: Int32 = 0
                let result = waitpid(processIdentifier, &status, WNOHANG)
                if result == processIdentifier {
                    exitStatus = status
                    return status
                }
                if result == 0 || (result == -1 && errno == EINTR) { return nil }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD)
            }
        }

        func cleanUp() throws {
            guard try pollExit() == nil else { return }
            // No other reaper owns this child. Until waitpid observes and reaps
            // exit, the PID remains reserved even if the child exits meanwhile.
            if kill(processIdentifier, SIGKILL) != 0 && errno != ESRCH {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let start = DispatchTime.now().uptimeNanoseconds
            repeat {
                if try pollExit() != nil { return }
                usleep(1_000)
            } while DispatchTime.now().uptimeNanoseconds - start < 1_000_000_000
            throw FixtureError.cleanupDeadline
        }
    }
}
