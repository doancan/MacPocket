import XCTest
@testable import MacPocketCore

/// Regression coverage for destructive-path and resource-safety hardening.
final class CoreHardeningTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-hardening-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        return try canonicalFileURL(root)
    }

    func testPackageContentsCountButAreNeverOfferedIndividually() async throws {
        let root = try fixture()
        let resources = root.appendingPathComponent("Sample.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("inside-bundle".utf8).write(to: resources.appendingPathComponent("asset.bin"))
        try Data("loose".utf8).write(to: root.appendingPathComponent("loose.txt"))

        let report = try await FileScanner().scan(root)
        XCTAssertEqual(report.fileCount, 2)
        XCTAssertEqual(report.bytes, 18)
        XCTAssertEqual(report.files.map(\.url.lastPathComponent), ["loose.txt"])
        XCTAssertEqual(report.packagedFileCount, 1)
        XCTAssertTrue(report.retainedAllFiles)
        XCTAssertEqual(report.folders.first?.url.lastPathComponent, "Sample.app")

        let asset = resources.appendingPathComponent("asset.bin")
        let request = FileTrashRequest(url: asset, identity: try FileIdentity.read(asset), root: root)
        XCTAssertThrowsError(try request.validate()) { error in
            guard case FileServiceError.insidePackage = error else { return XCTFail("Unexpected \(error)") }
        }
        let bundle = root.appendingPathComponent("Sample.app")
        XCTAssertNoThrow(try FileTrashRequest(url: bundle, identity: try FileIdentity.read(bundle), root: root).validate())
    }

    func testDuplicateComparisonSkipsUnreadableFileInsteadOfFailing() async throws {
        let root = try fixture()
        for name in ["a", "b", "locked"] {
            try Data("same-content".utf8).write(to: root.appendingPathComponent(name))
        }
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        addTeardownBlock { _ = try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let report = try await FileScanner().scan(root)
        let progressCalls = ProgressCounter()
        let groups = try await DuplicateFinder().groups(in: report.files) { _, _ in await progressCalls.increment() }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.url.lastPathComponent)), ["a", "b"])
        let calls = await progressCalls.value
        XCTAssertEqual(calls, 3, "Progress must advance for skipped files too")
    }

    func testSessionCriticalProcessesAreProtected() {
        XCTAssertTrue(ProcessMonitor.isSessionCritical("/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"))
        XCTAssertTrue(ProcessMonitor.isSessionCritical("/usr/libexec/trustd"))
        XCTAssertTrue(ProcessMonitor.isSessionCritical("/System/Library/PrivateFrameworks/Foo.framework/Versions/A/foo"))
        XCTAssertFalse(ProcessMonitor.isSessionCritical("/System/Applications/Mail.app/Contents/MacOS/Mail"))
        XCTAssertFalse(ProcessMonitor.isSessionCritical("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
        XCTAssertFalse(ProcessMonitor.isSessionCritical("/bin/sleep"))
    }

    func testSeparateErrorOutputKeepsStdoutParseable() throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sh", arguments: ["-c", "echo '{\"ok\":1}'; echo 'warning {x}' >&2"],
                                                   separateErrorOutput: true)
        let result = try runner.execute()
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "{\"ok\":1}")
        XCTAssertTrue(result.errorOutput.contains("warning"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testChattyLongRunningCommandIsNotKilledAtOutputLimit() throws {
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sh", arguments: ["-c", "seq 1 5000; exit 3"],
                                                   outputLimit: 64, stopOnOutputLimit: false)
        let result = try runner.execute()
        XCTAssertEqual(result.output.utf8.count, 64)
        XCTAssertEqual(result.exitCode, 3, "The process must run to completion")
    }

    func testOrphanedGrandchildHoldingPipeDoesNotHangExecution() throws {
        // The background sleep inherits stdout and outlives the shell; reading must still finish.
        let runner = SystemDiagnosticCommandRunner(executable: "/bin/sh", arguments: ["-c", "sleep 30 & echo started"])
        let started = Date()
        let result = try runner.execute()
        XCTAssertTrue(result.output.contains("started"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testUsedMemoryMatchesActivityMonitorComposition() {
        var snapshot = SystemSnapshot(capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 1,
                                      cpuUserPercent: 30, cpuSystemPercent: 80, cpuIdlePercent: 0, physicalMemoryBytes: 1_000,
                                      freeMemoryBytes: 100, wiredMemoryBytes: 200, compressedMemoryBytes: 50, uptimeSeconds: 1,
                                      thermalState: "nominal", volumes: [],
                                      power: .init(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil, lowPowerMode: false))
        XCTAssertNil(snapshot.usedMemoryBytes)
        snapshot.appMemoryBytes = 300
        XCTAssertEqual(snapshot.usedMemoryBytes, 550)
        XCTAssertEqual(snapshot.cpuTotalPercent, 100, "Clamped to 100")
    }
}

private actor ProgressCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
