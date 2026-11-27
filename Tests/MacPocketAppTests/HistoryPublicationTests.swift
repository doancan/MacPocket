import Combine
import Observation
import Synchronization
import XCTest
import MacPocketCore
@testable import MacPocketApp

private func historySnapshot(_ index: Int) throws -> SystemSnapshot {
    try JSONDecoder().decode(SystemSnapshot.self, from: Data("""
        {"capturedAt":\(index),"hardwareModel":"Fixture","logicalCPUCount":1,"cpuUserPercent":0,"cpuSystemPercent":0,"cpuIdlePercent":100,"physicalMemoryBytes":1024,"freeMemoryBytes":768,"wiredMemoryBytes":100,"compressedMemoryBytes":0,"uptimeSeconds":100,"thermalState":"nominal","volumes":[],"power":{"source":"AC","batteryPresent":false,"lowPowerMode":false}}
        """.utf8))
}
private actor HistoryReader {
    var nextIndex = 0
    func read() throws -> SystemSnapshot { defer { nextIndex += 1 }; return try historySnapshot(nextIndex) }
}

@MainActor final class HistoryPublicationTests: XCTestCase {
    func testFullMenuHistoryPublishesOnlyOneBoundedValuePerSample() throws {
        let history = MenuBarHistory()
        for i in 0..<MenuBarHistory.capacity { history.record(try historySnapshot(i)) }
        var counts: [Int] = [], notifications = 0
        let values = history.$samples.dropFirst().sink { counts.append($0.count) }
        let changes = history.objectWillChange.sink { notifications += 1 }
        defer { values.cancel(); changes.cancel() }
        for i in MenuBarHistory.capacity..<MenuBarHistory.capacity + 20 { history.record(try historySnapshot(i)) }
        XCTAssertEqual(counts, Array(repeating: MenuBarHistory.capacity, count: 20))
        XCTAssertEqual(notifications, 20)
        XCTAssertEqual(history.samples.first?.date, Date(timeIntervalSinceReferenceDate: 20))
        XCTAssertEqual(history.samples.last?.date, Date(timeIntervalSinceReferenceDate: 109))
    }
    func testDuplicateMenuSampleDoesNotPublish() throws {
        let history = MenuBarHistory(), snapshot = try historySnapshot(1)
        history.record(snapshot)
        var updates = 0
        let subscription = history.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }
        history.record(snapshot)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(history.samples.count, 1)
    }
    func testFullSystemHistoryPublishesOnceAndKeepsNewestSamples() async {
        let reader = HistoryReader()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket.HistoryPublication." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PocketModel(startMonitoring: false, readSystemSnapshot: { try await reader.read() },
            historyStore: PowerHistoryStore(url: directory.appendingPathComponent("history.json")))
        for _ in 0..<PocketModel.sampleCapacity { await model.refresh(includeProcesses: false) }
        var counts: [Int] = []
        for _ in 0..<20 {
            let changes = Mutex(0)
            withObservationTracking { _ = model.samples } onChange: { changes.withLock { $0 += 1 } }
            await model.refresh(includeProcesses: false)
            XCTAssertEqual(changes.withLock { $0 }, 1)
            counts.append(model.samples.count)
        }
        XCTAssertEqual(counts, Array(repeating: PocketModel.sampleCapacity, count: 20))
        XCTAssertEqual(model.samples.first?.date, Date(timeIntervalSinceReferenceDate: 20))
        XCTAssertEqual(model.samples.last?.date, Date(timeIntervalSinceReferenceDate: 169))
    }
}

/// With Observation, a monitoring sample must not invalidate views that never read live metrics.
@MainActor final class PocketModelObservationTests: XCTestCase {
    func testSystemRefreshDoesNotInvalidateUnrelatedReaders() async {
        let reader = HistoryReader()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket.Observation." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PocketModel(startMonitoring: false, readSystemSnapshot: { try await reader.read() },
            historyStore: PowerHistoryStore(url: directory.appendingPathComponent("history.json")))
        await model.refresh(includeProcesses: false)
        let unrelated = Mutex(0), live = Mutex(0)
        withObservationTracking { _ = model.refreshSeconds; _ = model.paused; _ = model.awakeSession } onChange: { unrelated.withLock { $0 += 1 } }
        withObservationTracking { _ = model.system } onChange: { live.withLock { $0 += 1 } }
        await model.refresh(includeProcesses: false)
        XCTAssertEqual(unrelated.withLock { $0 }, 0)
        XCTAssertEqual(live.withLock { $0 }, 1)
    }
}
