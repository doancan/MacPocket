import XCTest
@testable import MacPocketCore

final class MacUtilityServiceTests: XCTestCase {
    func testCatalogUsesInstalledExecutablesAndReadOnlyQueries() {
        XCTAssertEqual(Set(MacUtility.allCases.map(\.id)).count, MacUtility.allCases.count)
        for tool in MacUtility.allCases {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool.command.0), tool.id)
            XCTAssertFalse(tool.command.1.contains("--install"), tool.id)
            XCTAssertFalse(tool.command.1.contains("delete"), tool.id)
        }
    }
    func testServicePreservesBoundedPartialOutput() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/usr/bin/printf", arguments: ["abcdef"], outputLimit: 3)
        let report = try await MacUtilityService.run(.dns, runner: runner)
        XCTAssertEqual(report.output, "abc")
        XCTAssertEqual(report.completion, .outputLimit)
        XCTAssertTrue(report.truncated)
        XCTAssertNil(report.exitCode)
    }
    func testServiceDeadlineReportsUnknownExitRatherThanSuccess() async throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["2"], timeout: 0.03)
        let report = try await MacUtilityService.run(.timeMachine, runner: runner)
        XCTAssertEqual(report.completion, .timedOut)
        XCTAssertTrue(report.partial)
        XCTAssertNil(report.exitCode)
    }
    func testCancelledOperationDoesNotBecomeEmptySuccessfulReport() async {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sleep", arguments: ["2"])
        runner.cancel()
        do { _ = try await MacUtilityService.run(.spotlight, runner: runner); XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    func testLiveTimeMachineQueryRetainsSourceAndStatus() async throws {
        let report = try await MacUtilityService.run(.timeMachine)
        XCTAssertEqual(report.id, MacUtility.timeMachine.id)
        XCTAssertEqual(report.completion, .complete)
        XCTAssertNotNil(report.exitCode)
        XCTAssertFalse(report.output.isEmpty)
        // An empty snapshot list is valid and must not be presented as a failure.
        if report.exitCode == 0 { XCTAssertFalse(report.partial) }
    }
}
