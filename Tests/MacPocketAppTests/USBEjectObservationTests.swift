import XCTest
import MacPocketCore
@testable import MacPocketApp

private actor DiskListFixture {
    private(set) var reads = 0
    var drives: [EjectDrive] = []
    private var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?
    func set(_ drives: [EjectDrive]) { self.drives = drives }
    func block() { blocked = true }
    func unblock() { blocked = false; continuation?.resume(); continuation = nil }
    func load() async -> [EjectDrive] {
        reads += 1
        let snapshot = drives
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return snapshot
    }
}

@MainActor private final class DiskEventsFixture {
    var callbacks: [UUID: @MainActor () -> Void] = [:]
    private(set) var stops = 0
    func observe(_ receive: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)? {
        let id = UUID()
        callbacks[id] = receive
        receive()
        return { self.callbacks[id] = nil; self.stops += 1 }
    }
    func fire() { for callback in callbacks.values { callback() } }
}

@MainActor final class USBEjectObservationTests: XCTestCase {
    private func fixture() -> (USBEjectModel, DiskListFixture, DiskEventsFixture) {
        let reader = DiskListFixture(), events = DiskEventsFixture()
        return (USBEjectModel(loadDrives: { await reader.load() }, observeChanges: events.observe), reader, events)
    }
    private func wait(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<800 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
    private func drive(identity: String) -> EjectDrive {
        EjectDrive(id: "disk99", identity: identity, name: "Fixture", connection: "USB", capacity: 1000, volumes: [])
    }

    func testUnchangedDiskListDoesNotPollAndCancellationRemovesObserver() async {
        let (model, reader, events) = fixture()
        let task = Task { await model.run() }
        let loaded = await wait { model.loaded }
        XCTAssertTrue(loaded)
        try? await Task.sleep(for: .milliseconds(3200))
        let reads = await reader.reads
        XCTAssertEqual(reads, 1)
        task.cancel()
        await task.value
        XCTAssertEqual(events.stops, 1)
        XCTAssertTrue(events.callbacks.isEmpty)
    }

    func testEventBurstDuringReadKeepsOneFollowupWithLatestDiskIdentity() async {
        let (model, reader, events) = fixture()
        await reader.set([drive(identity: "old")])
        await reader.block()
        let task = Task { await model.run() }
        let started = await wait { await reader.reads == 1 }
        XCTAssertTrue(started)
        await reader.set([drive(identity: "new")])
        for _ in 0..<100 { events.fire() }
        await reader.unblock()
        let updated = await wait { model.drives.first?.identity == "new" }
        XCTAssertTrue(updated)
        let reads = await reader.reads
        XCTAssertEqual(reads, 2)
        task.cancel()
        await task.value
    }

    func testReusedBSDIDClearsSelectionButUnchangedIdentityKeepsIt() async {
        let (model, reader, events) = fixture()
        await reader.set([drive(identity: "old")])
        let task = Task { await model.run() }
        let initial = await wait { model.loaded }
        XCTAssertTrue(initial)
        model.selection = ["disk99"]
        model.expanded = ["disk99"]
        events.fire()
        let unchanged = await wait { await reader.reads == 2 }
        XCTAssertTrue(unchanged)
        XCTAssertEqual(model.selection, ["disk99"])
        await reader.set([drive(identity: "replacement")])
        events.fire()
        let replaced = await wait { model.drives.first?.identity == "replacement" }
        XCTAssertTrue(replaced)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.expanded.isEmpty)
        task.cancel()
        await task.value
    }

    func testEventDuringManualRefreshIsNotLost() async {
        let (model, reader, events) = fixture()
        let task = Task { await model.run() }
        let initial = await wait { model.loaded }
        XCTAssertTrue(initial)
        await reader.block()
        let manual = Task { await model.refresh() }
        let started = await wait { await reader.reads == 2 }
        XCTAssertTrue(started)
        await reader.set([drive(identity: "new")])
        events.fire()
        // Let the stream consume the event while the manual read is still suspended.
        for _ in 0..<20 { await Task.yield() }
        await reader.unblock()
        await manual.value
        let updated = await wait { model.drives.first?.identity == "new" }
        XCTAssertTrue(updated)
        let reads = await reader.reads
        XCTAssertEqual(reads, 3)
        task.cancel()
        await task.value
    }

    func testRestartDuringCancelledReadReceivesPendingInitialRefresh() async {
        let (model, reader, events) = fixture()
        await reader.block()
        let old = Task { await model.run() }
        let started = await wait { await reader.reads == 1 }
        XCTAssertTrue(started)
        old.cancel()
        let replacement = Task { await model.run() }
        let subscribed = await wait { events.callbacks.count == 2 }
        XCTAssertTrue(subscribed)
        for _ in 0..<20 { await Task.yield() }
        await reader.set([drive(identity: "latest")])
        await reader.unblock()
        await old.value
        let updated = await wait { model.drives.first?.identity == "latest" }
        XCTAssertTrue(updated)
        replacement.cancel()
        await replacement.value
        XCTAssertEqual(events.stops, 2)
    }

    func testUnavailableObservationFallsBackToPeriodicDiscovery() async {
        let reader = DiskListFixture()
        let model = USBEjectModel(loadDrives: { await reader.load() }, observeChanges: { _ in nil })
        let task = Task { await model.run() }
        let refreshed = await wait { await reader.reads == 2 }
        XCTAssertTrue(refreshed)
        task.cancel()
        await task.value
    }
}
