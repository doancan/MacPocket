import XCTest
@testable import MacPocketCore

final class PowerHistoryTests: XCTestCase {
    private func url() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-history-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("history.json")
    }
    private func snapshot(_ seconds: TimeInterval) -> SystemSnapshot {
        .init(capturedAt: Date(timeIntervalSince1970: seconds), hardwareModel: "fixture", logicalCPUCount: 2,
              cpuUserPercent: nil, cpuSystemPercent: nil, cpuIdlePercent: nil, physicalMemoryBytes: 1024,
              freeMemoryBytes: 100, wiredMemoryBytes: 200, compressedMemoryBytes: 50, uptimeSeconds: 100,
              thermalState: "nominal", volumes: [], power: .init(source: "AC Power", batteryPresent: false,
              chargePercent: nil, isCharging: nil, lowPowerMode: false))
    }
    func testSamplingIntervalAndExplicitSleepEvents() async throws {
        let store = PowerHistoryStore(url: url())
        _ = try await store.record(snapshot(100))
        let suppressed = try await store.record(snapshot(110))
        XCTAssertNil(suppressed)
        _ = try await store.record(snapshot(111), event: "Uyku")
        let records = try await store.entries()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.event, "Uyku")
        XCTAssertNil(records.first?.chargePercent)
    }
    func testBoundedHistoryReloadsAcrossInstances() async throws {
        let url = url()
        let store = PowerHistoryStore(url: url, maximumEntries: 2)
        for second in [100.0, 200.0, 300.0] { _ = try await store.record(snapshot(second)) }
        let reloaded = try await PowerHistoryStore(url: url, maximumEntries: 2).entries()
        XCTAssertEqual(reloaded.map { $0.date.timeIntervalSince1970 }, [200, 300])
    }
    func testCorruptHistoryIsNotSilentlyOverwritten() async throws {
        let url = url()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid history".utf8)
        try original.write(to: url)
        do { _ = try await PowerHistoryStore(url: url).record(snapshot(100)); XCTFail("Accepted corrupt history") }
        catch { }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
