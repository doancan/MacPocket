import XCTest
import MacPocketCore
@testable import MacPocketApp

private actor CableAuditInventory {
    var inventory: CableInventory
    var failing = false
    init(_ inventory: CableInventory) { self.inventory = inventory }
    func read() throws -> CableInventory {
        if failing { throw NSError(domain: "Fixture", code: 1) }
        return inventory
    }
    func replace(_ value: CableInventory) { inventory = value }
    func fail() { failing = true }
}

private actor CableAuditGate {
    var pending: CheckedContinuation<Void, Never>?
    var released = false
    var waiting: Bool { pending != nil }
    func scan(_ connection: CableConnection, _ inventory: CableInventory, _ extra: Set<String>, _ manual: Set<String>) async throws -> CableImpactReport {
        let result = try await CableImpactScanner.scan(connection: connection, inventory: inventory, additionalConnections: extra, manualEndpoints: manual)
        if connection.id == "1" && !released { await withCheckedContinuation { pending = $0 } }
        return result
    }
    func release() { released = true; pending?.resume(); pending = nil }
}

@MainActor final class CableImpactModelTests: XCTestCase {
    private func fixture(replacement: Bool = false, reversed: Bool = false) -> CableInventory {
        let first: UInt64 = replacement ? 100 : 1
        var nodes: [CableRegistryNode] = [.init(id: first, name: "Dock A", kind: .usb), .init(id: 2, name: "Dock B", kind: .usb),
                                          .init(id: 11, parents: [first], name: "SSD", kind: .media)]
        if reversed { nodes.reverse() }
        return .init(nodes: nodes, connections: CableTopology.connections(in: nodes), endpoints: [
            .init(id: "disk", name: "SSD", kind: .storage, registryIDs: [11]),
            .init(id: "display", name: "Monitor", kind: .display)
        ])
    }
    private func eventually(_ predicate: () async -> Bool) async -> Bool {
        for _ in 0..<100 {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    func testLateResultCannotReplaceNewSelection() async {
        let inventory = fixture(), gate = CableAuditGate()
        addTeardownBlock { await gate.release() }
        let model = CableImpactModel(read: { inventory }, scan: { try await gate.scan($0, $1, $2, $3) }, stillPresent: { _ in true })
        await model.refresh()
        let waiting = await eventually { await gate.waiting }; XCTAssertTrue(waiting)
        model.select("2")
        let current = await eventually { model.report?.connectionID == "2" }; XCTAssertTrue(current)
        await gate.release()
        await Task.yield()
        XCTAssertEqual(model.report?.connectionID, "2"); XCTAssertFalse(model.scanning)
    }
    func testStopAndCancelRejectLateResults() async {
        for cancel in [false, true] {
            let inventory = fixture(), gate = CableAuditGate()
            let model = CableImpactModel(read: { inventory }, scan: { try await gate.scan($0, $1, $2, $3) }, stillPresent: { _ in true })
            await model.refresh()
            let waiting = await eventually { await gate.waiting }; XCTAssertTrue(waiting)
            if cancel { model.cancel() } else { model.stop() }
            await gate.release(); await Task.yield()
            XCTAssertNil(model.report); XCTAssertFalse(model.scanning)
            XCTAssertEqual(model.failure != nil, cancel)
        }
    }
    func testDisappearingDependencyInvalidatesWholeOldMap() async {
        let inventory = fixture()
        let model = CableImpactModel(read: { inventory }, stillPresent: { ids in !ids.contains(11) })
        await model.refresh()
        let finished = await eventually { !model.scanning }; XCTAssertTrue(finished)
        XCTAssertNil(model.inventory); XCTAssertNil(model.report); XCTAssertNil(model.selectedID)
        XCTAssertNotNil(model.failure); XCTAssertTrue(model.affected.isEmpty)
    }
    func testFailureOnRefreshDoesNotLeaveLastInventoryLookingCurrent() async {
        let box = CableAuditInventory(fixture())
        let model = CableImpactModel(read: { try await box.read() }, stillPresent: { _ in true })
        await model.refresh()
        let completed = await eventually { model.report != nil }; XCTAssertTrue(completed)
        await box.fail(); await model.refresh()
        XCTAssertNil(model.inventory); XCTAssertNil(model.report); XCTAssertNotNil(model.failure)
    }
    func testManualPairsRemainExplicitAndAreClearedOnHardwareReplacement() async {
        let box = CableAuditInventory(fixture())
        let model = CableImpactModel(read: { try await box.read() }, stillPresent: { _ in true })
        await model.refresh(); model.pairEndpoint("display", enabled: true)
        let paired = await eventually { model.report?.affected.contains { $0.id == "display" && $0.evidence == .manual } == true }
        XCTAssertTrue(paired)
        await box.replace(fixture(reversed: true)); await model.refresh()
        XCTAssertTrue(model.manualEndpoints["1"]?.contains("display") == true, "Registry iteration order is not a hardware change")
        await box.replace(fixture(replacement: true)); await model.refresh()
        XCTAssertTrue(model.manualEndpoints.isEmpty); XCTAssertNotNil(model.mappingNotice)
        XCTAssertFalse(model.affected.contains { $0.id == "display" })
    }
    func testPeerConnectionAndEmptyInventoryNeverInventAnEffect() async {
        let inventory = fixture()
        let model = CableImpactModel(read: { inventory }, stillPresent: { _ in true })
        await model.refresh(); model.select("2"); model.pairConnection("1", enabled: true)
        XCTAssertEqual(model.affected.first?.evidence, .manual)
        model.pairConnection("1", enabled: false)
        XCTAssertTrue(model.affected.isEmpty)
        let empty = CableImpactModel(read: { .init(nodes: [], connections: [], endpoints: []) })
        await empty.refresh()
        XCTAssertTrue(empty.loaded); XCTAssertNil(empty.selection); XCTAssertNil(empty.report); XCTAssertFalse(empty.scanning)
        model.stop()
    }
}
