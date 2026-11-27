import XCTest
import MacPocketCore
@testable import MacPocketApp

private actor SamplingReaders {
    private(set) var systems = 0
    private(set) var processes = 0
    var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?
    func block() { blocked = true }
    func release() { blocked = false; continuation?.resume(); continuation = nil }
    func system() async throws -> SystemSnapshot {
        systems += 1
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return try JSONDecoder().decode(SystemSnapshot.self, from: Data(#"{"capturedAt":0,"hardwareModel":"Fixture","logicalCPUCount":1,"physicalMemoryBytes":1024,"freeMemoryBytes":768,"wiredMemoryBytes":100,"compressedMemoryBytes":0,"uptimeSeconds":100,"thermalState":"nominal","volumes":[],"power":{"source":"AC","batteryPresent":false,"lowPowerMode":false}}"#.utf8))
    }
    func process() throws -> ProcessSnapshot {
        processes += 1
        return try JSONDecoder().decode(ProcessSnapshot.self, from: Data(#"{"capturedAt":0,"processes":[],"listedProcessCount":0,"unreadableProcessCount":0}"#.utf8))
    }
}

@MainActor final class ProcessSamplingDemandTests: XCTestCase {
    private func fixture() -> (PocketModel, SamplingReaders) {
        let reads = SamplingReaders()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket.SamplingTests." + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let model = PocketModel(startMonitoring: false, readSystemSnapshot: { try await reads.system() },
            readProcessSnapshot: { try await reads.process() }, historyStore: PowerHistoryStore(url: directory.appendingPathComponent("history.json")))
        return (model, reads)
    }
    private func wait(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
    func testHiddenTaskManagerDoesNotScanButSystemTelemetryContinues() async {
        let (model, reads) = fixture()
        model.navigation.open(.taskManager)
        for _ in 0..<3 { await model.refresh() }
        let systems = await reads.systems, processes = await reads.processes
        XCTAssertEqual(systems, 3)
        XCTAssertEqual(processes, 0)
    }
    func testVisibleTaskManagerResumesImmediatelyAndStopsWhenHidden() async {
        let (model, reads) = fixture()
        model.navigation.open(.taskManager)
        model.setMainWindowVisible(true)
        let resumed = await wait { await reads.processes == 1 }
        XCTAssertTrue(resumed)
        model.setMainWindowVisible(false)
        for _ in 0..<3 { await model.refresh() }
        let hiddenCount = await reads.processes
        XCTAssertEqual(hiddenCount, 1)
        model.setMainWindowVisible(true)
        let restored = await wait { await reads.processes == 2 }
        XCTAssertTrue(restored)
        model.setMainWindowVisible(false)
    }
    func testOtherPagesDoNotRequestProcessesAndExplicitReportsCanForceThem() async {
        let (model, reads) = fixture()
        model.setMainWindowVisible(true)
        await model.refresh()
        let normalCount = await reads.processes
        XCTAssertEqual(normalCount, 0)
        await model.refresh(includeProcesses: true)
        let forcedCount = await reads.processes
        XCTAssertEqual(forcedCount, 1)
        model.setMainWindowVisible(false)
    }
    func testOpenMenuBarProcessListKeepsSamplingWithMainWindowHidden() async {
        let (model, reads) = fixture()
        model.menuBarProcessesWanted = true
        for _ in 0..<3 { await model.refresh() }
        let shownCount = await reads.processes
        XCTAssertEqual(shownCount, 3)
        model.menuBarProcessesWanted = false
        await model.refresh()
        let closedCount = await reads.processes
        XCTAssertEqual(closedCount, 3)
        // Opening the menu during an existing system-only read must queue its automatic demand.
        await reads.block()
        let existing = Task { await model.refresh(includeProcesses: false) }
        let entered = await wait { await reads.systems == 5 }
        XCTAssertTrue(entered)
        model.menuBarProcessesWanted = true
        await model.refresh()
        await reads.release()
        await existing.value
        let resumed = await wait { await reads.processes == 4 }
        XCTAssertTrue(resumed)
        model.menuBarProcessesWanted = false
    }
    func testPausedWindowRestorationDoesNotStartAutomaticRead() async {
        let (model, reads) = fixture()
        model.navigation.open(.taskManager)
        model.paused = true
        model.setMainWindowVisible(true)
        await Task.yield()
        let count = await reads.systems
        XCTAssertEqual(count, 0)
        model.setMainWindowVisible(false)
    }
    func testVisibilityIsResolvedAfterAwaitAndRequestsAreCoalesced() async {
        let (model, reads) = fixture()
        model.navigation.open(.taskManager)
        await reads.block()
        let refresh = Task { await model.refresh() }
        let entered = await wait { await reads.systems == 1 }
        XCTAssertTrue(entered)
        model.setMainWindowVisible(true)
        await Task.yield()
        await reads.release()
        await refresh.value
        try? await Task.sleep(for: .milliseconds(30))
        let count = await reads.processes
        XCTAssertEqual(count, 1)
        model.setMainWindowVisible(false)
    }
    func testWindowHiddenDuringInFlightReadCancelsAutomaticProcessDemand() async {
        let (model, reads) = fixture()
        model.navigation.open(.taskManager)
        await reads.block()
        let refresh = Task { await model.refresh() }
        let entered = await wait { await reads.systems == 1 }
        XCTAssertTrue(entered)
        model.setMainWindowVisible(true)
        await Task.yield()
        model.setMainWindowVisible(false)
        await reads.release()
        await refresh.value
        try? await Task.sleep(for: .milliseconds(30))
        let count = await reads.processes
        XCTAssertEqual(count, 0)
    }
}
