import XCTest
@testable import MacPocketCore

final class SystemMonitorTests: XCTestCase {
    func testFirstOrChangedCPUCountIsUnavailable() {
        let ticks = [SystemCPUTicks(user: 20, system: 10, idle: 70, nice: 0)]
        XCTAssertNil(SystemCPUDelta.percentages(previous: nil, current: ticks))
        XCTAssertNil(SystemCPUDelta.percentages(previous: [], current: ticks))
        XCTAssertNil(SystemCPUDelta.percentages(previous: ticks, current: ticks))
    }

    func testCPUDeltaUsesIntervalAndIncludesNiceInUser() throws {
        let old = [SystemCPUTicks(user: 5_000, system: 2_000, idle: 90_000, nice: 300)]
        let new = [SystemCPUTicks(user: 5_010, system: 2_020, idle: 90_060, nice: 310)]
        let result = try XCTUnwrap(SystemCPUDelta.percentages(previous: old, current: new))
        XCTAssertEqual(result.user, 20, accuracy: 0.0001)
        XCTAssertEqual(result.system, 20, accuracy: 0.0001)
        XCTAssertEqual(result.idle, 60, accuracy: 0.0001)
    }

    func testCPUCounterRolloverIsHandledPerCounter() throws {
        let old = [SystemCPUTicks(user: UInt32.max - 4, system: 5, idle: 50, nice: 0)]
        let new = [SystemCPUTicks(user: 5, system: 15, idle: 130, nice: 0)]
        let result = try XCTUnwrap(SystemCPUDelta.percentages(previous: old, current: new))
        XCTAssertEqual(result.user, 10, accuracy: 0.0001)
        XCTAssertEqual(result.system, 10, accuracy: 0.0001)
        XCTAssertEqual(result.idle, 80, accuracy: 0.0001)
    }

    func testLiveSnapshotHasConsistentHostData() async throws {
        let monitor = SystemMonitor()
        let first = try await monitor.snapshot()
        XCTAssertGreaterThan(first.logicalCPUCount, 0)
        XCTAssertGreaterThan(first.physicalMemoryBytes, 0)
        XCTAssertFalse(first.hardwareModel.isEmpty)
        XCTAssertNil(first.cpuUserPercent)
        XCTAssertLessThanOrEqual(first.freeMemoryBytes, first.physicalMemoryBytes)
        if !first.power.batteryPresent {
            XCTAssertNil(first.power.chargePercent)
            XCTAssertNil(first.power.isCharging)
        }
        try await Task.sleep(for: .milliseconds(150))
        let second = try await monitor.snapshot()
        let user = try XCTUnwrap(second.cpuUserPercent)
        let system = try XCTUnwrap(second.cpuSystemPercent)
        let idle = try XCTUnwrap(second.cpuIdlePercent)
        XCTAssertEqual(user + system + idle, 100, accuracy: 0.001)
        XCTAssertTrue(second.volumes.allSatisfy { $0.totalBytes > 0 && $0.availableBytes >= 0 })
    }

    func testQueryOnlyDiagnosticProducesBoundedReport() async throws {
        let report = try await SystemDiagnostics.run(.swap)
        XCTAssertEqual(report.exitCode, 0)
        XCTAssertEqual(report.completion, .complete)
        XCTAssertFalse(report.partial)
        XCTAssertFalse(report.truncated)
        XCTAssertTrue(report.output.contains("vm.swapusage"))
        XCTAssertLessThanOrEqual(report.output.utf8.count, 262_144)
    }

    func testDiagnosticDeadlineTerminatesOwnedSleep() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["20"], timeout: 0.1)
        do {
            _ = try await Task.detached { try runner.execute() }.value
            XCTFail("Expected a deadline error")
        } catch SystemDiagnosticError.timedOut { }
    }

    func testDiagnosticOutputCapIsEnforced() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/usr/bin/yes", arguments: [], outputLimit: 512)
        do {
            _ = try await Task.detached { try runner.execute() }.value
            XCTFail("Expected an output-limit error")
        } catch let SystemDiagnosticError.outputLimit(output) {
            XCTAssertEqual(output.utf8.count, 512)
        }
    }

    func testCancelledDiagnosticNeverLaunches() throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["20"])
        runner.cancel()
        XCTAssertThrowsError(try runner.execute()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCancellationStopsOwnedRunningDiagnostic() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["20"])
        let task = Task.detached { try runner.execute() }
        try await Task.sleep(for: .milliseconds(100))
        runner.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testServiceRetainsStructuredPartialOutputWhenLimitIsReached() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/usr/bin/yes", arguments: [], outputLimit: 512)
        let report = try await SystemDiagnostics.run(.openFiles, runner: runner)
        XCTAssertEqual(report.completion, .outputLimit)
        XCTAssertTrue(report.partial)
        XCTAssertTrue(report.truncated)
        XCTAssertNil(report.exitCode)
        XCTAssertEqual(report.output.utf8.count, 512)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        XCTAssertEqual(encoded?["completion"] as? String, "outputLimit")
        XCTAssertEqual(encoded?["partial"] as? Bool, true)
    }

    func testServiceRetainsStructuredTimeoutWithoutInventingExitStatus() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["20"], timeout: 0.1)
        let report = try await SystemDiagnostics.run(.openFiles, runner: runner)
        XCTAssertEqual(report.completion, .timedOut)
        XCTAssertTrue(report.partial)
        XCTAssertFalse(report.truncated)
        XCTAssertNil(report.exitCode)
    }

    func testServiceCancellationRemainsAnError() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["20"])
        runner.cancel()
        do {
            _ = try await SystemDiagnostics.run(.openFiles, runner: runner)
            XCTFail("Expected cancellation, not a partial successful report")
        } catch is CancellationError { }
    }

    func testOpenFilesPIDIsExactAndCannotBroadenToUserFilter() throws {
        let command = try SystemDiagnostic.openFiles.command(processID: 123)
        XCTAssertEqual(command.executable, "/usr/sbin/lsof")
        XCTAssertEqual(command.arguments, ["-nP", "-p", "123"])
        XCTAssertThrowsError(try SystemDiagnostic.openFiles.command(processID: 0))
        XCTAssertThrowsError(try SystemDiagnostic.openFiles.command(processID: -1))
        XCTAssertThrowsError(try SystemDiagnostic.swap.command(processID: 123))
    }
}
