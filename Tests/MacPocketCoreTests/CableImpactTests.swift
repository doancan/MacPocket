import XCTest
@testable import MacPocketCore

@MainActor final class CableImpactTests: XCTestCase {
    private func fixture(duplicateAddress: Bool = false, owners: [String: Set<String>] = [:]) -> CableInventory {
        let nodes: [CableRegistryNode] = [
            .init(id: 1, name: "Dock", kind: .usb), .init(id: 2, parents: [1], name: "Hub", kind: .usb),
            .init(id: 3, parents: [2], name: "SSD", kind: .media), .init(id: 4, parents: [1], name: "Ethernet", kind: .network),
            .init(id: 5, name: "Other dock", kind: .usb), .init(id: 6, parents: [5], name: "Other Ethernet", kind: .network)
        ]
        let endpoints: [CableEndpoint] = [
            .init(id: "disk", name: "Project", kind: .storage, registryIDs: [3], active: true),
            .init(id: "network", name: "Ethernet", kind: .network, registryIDs: [4], interfaceName: "en9", addresses: ["10.0.0.2", "2001:db8::1"]),
            .init(id: "other", name: "Other Ethernet", kind: .network, registryIDs: [6], interfaceName: "en10", addresses: duplicateAddress ? ["10.0.0.2"] : ["10.0.1.2"]),
            .init(id: "screen", name: "Dock", kind: .display)
        ]
        let drive = EjectDrive(id: "disk9", identity: "owned", name: "Project", connection: "USB", capacity: 100,
                               volumes: [.init(id: "disk9s1", name: "Project", mountPath: "/Volumes/Project Data")])
        return .init(nodes: nodes, connections: CableTopology.connections(in: nodes), endpoints: endpoints, drives: ["disk": drive], networkAddressInterfaces: owners)
    }
    private let tcp = "p4242\0cssh\0n10.0.0.2:50123->203.0.113.1:22\0\np4243\0ccurl\0n[2001:DB8:0:0::1]:50124->[2001:db8::9]:443\0\n"
    private func execute(_ path: String, _ arguments: [String], _ timeout: TimeInterval) async throws -> BoundedProcess.Result {
        XCTAssertEqual(path, "/usr/sbin/lsof")
        if arguments.contains("-iTCP") { return .init(status: 0, output: tcp, errorOutput: "") }
        XCTAssertEqual(arguments.suffix(2), ["--", "/Volumes/Project Data"])
        return .init(status: 0, output: "p4242\0ceditor\0f4\0n/Volumes/Project Data/draft.mov\0n/Volumes/Project Database/not-owned\0", errorOutput: "")
    }

    func testDescendantEffectsExcludeOtherDockAndIdenticallyNamedDisplay() throws {
        let inventory = fixture(), connection = try XCTUnwrap(inventory.connections.first { $0.roots == [1] })
        let effects = CableTopology.affected(connection: connection, inventory: inventory)
        XCTAssertEqual(Set(effects.map(\.id)), ["disk", "network"])
        XCTAssertTrue(effects.allSatisfy { $0.evidence == .registry })
        let manual = CableTopology.affected(connection: connection, inventory: inventory, additionalConnections: ["5"], manualEndpoints: ["screen"])
        XCTAssertEqual(manual.first { $0.id == "screen" }?.evidence, .manual)
        XCTAssertEqual(manual.first { $0.id == "other" }?.evidence, .manual)
        XCTAssertEqual(manual.first { $0.id == "disk" }?.evidence, .registry)
    }
    func testContainerIdentityGroupsFunctionsButNotZeroMissingOrInternalDevices() {
        let uuid = "98ee6de9-20ba-467c-97e1-5efde1574374"
        let nodes: [CableRegistryNode] = [
            .init(id: 1, name: "USB2", kind: .usb, containerID: uuid), .init(id: 2, name: "USB3", kind: .usb, containerID: uuid.uppercased()),
            .init(id: 3, name: "Internal", kind: .usb, containerID: uuid, builtIn: true),
            .init(id: 4, name: "Same name", kind: .usb), .init(id: 5, name: "Same name", kind: .usb),
            .init(id: 6, name: "Bad", kind: .usb, containerID: "invalid"),
            .init(id: 7, name: "Zero", kind: .usb, containerID: "00000000-0000-0000-0000-000000000000")
        ]
        let connections = CableTopology.connections(in: nodes)
        XCTAssertEqual(connections.count, 5)
        XCTAssertEqual(connections.first { $0.groupedByContainer }?.roots, [1, 2])
        XCTAssertFalse(connections.contains { $0.roots.contains(3) })
        XCTAssertNotEqual(CableConnection(name: "USB2", roots: [1]).id, CableConnection(name: "USB2", roots: [100]).id)
    }
    func testCyclicAndMultiParentRegistryCannotLoopOrLoseDependencies() {
        let nodes: [CableRegistryNode] = [.init(id: 1, parents: [3], name: "one"), .init(id: 2, parents: [1, 99], name: "two"), .init(id: 3, parents: [2], name: "three")]
        XCTAssertEqual(CableTopology.descendants(of: [1], in: nodes), [1, 2, 3])
        XCTAssertEqual(CableTopology.descendants(of: [99], in: nodes), [99, 1, 2, 3])
        XCTAssertEqual(CableTopology.descendants(of: [123], in: nodes), [123])
    }
    func testTCPParserCanonicalizesIPv6AndDoesNotInferSSHFromPort() {
        let parsed = CableSessionParser.parse(tcp + "p55\0ccurl\0n[::ffff:10.0.0.2]:234->10.0.0.9:22\0")
        XCTAssertEqual(parsed.sessions.count, 3)
        XCTAssertEqual(parsed.sessions.map(\.localAddress), ["10.0.0.2", "2001:db8::1", "10.0.0.2"])
        XCTAssertTrue(parsed.sessions[0].isSSH); XCTAssertFalse(parsed.sessions[2].isSSH)
        XCTAssertEqual(CableSessionParser.canonicalAddress("fe80::1%en9"), "fe80::1")
        XCTAssertNil(CableSessionParser.canonicalAddress("host.example"))
    }
    func testTCPParserRejectsListenersMalformedEndpointsAndDuplicates() {
        let parsed = CableSessionParser.parse(tcp + tcp + "p10\0cssh\0n*:22\0n10.0.0.2:0->10.0.0.3:22\0n10.0.0.2:123->name:22\0n10.0.0.2:123->10.0.0.3:99999\0")
        XCTAssertEqual(parsed.sessions.count, 2)
        let huge = (1...2001).map { "p\($0)\0capp\0n10.0.0.2:1234->10.0.0.3:443\0" }.joined()
        XCTAssertEqual(CableSessionParser.parse(huge).sessions.count, 2000)
        XCTAssertTrue(CableSessionParser.parse(huge).limited)
    }
    func testScanCombinesOnlyRelatedOpenFilesAndSessions() async throws {
        let inventory = fixture(), connection = try XCTUnwrap(inventory.connections.first { $0.roots == [1] })
        let report = try await CableImpactScanner.scan(connection: connection, inventory: inventory, execute: execute)
        XCTAssertEqual(report.diskUsers["disk"]?.first?.files, ["/Volumes/Project Data/draft.mov"])
        XCTAssertEqual(report.sessions["network"]?.map(\.pid), [4242, 4243])
        XCTAssertNil(report.sessions["other"])
        XCTAssertTrue(report.needsAttention); XCTAssertTrue(report.issues.isEmpty)
    }
    func testOverlappingAddressesAndWirelessOwnersRemainAmbiguous() async throws {
        for inventory in [fixture(duplicateAddress: true), fixture(owners: ["10.0.0.2": ["en9", "en0"], "2001:db8::1": ["en9"]])] {
            let connection = try XCTUnwrap(inventory.connections.first { $0.roots == [1] })
            let report = try await CableImpactScanner.scan(connection: connection, inventory: inventory, execute: execute)
            XCTAssertEqual(report.sessions["network"]?.map(\.pid), [4243])
            XCTAssertFalse(report.issues.isEmpty)
        }
    }
    func testReadFailuresStayUnknownRatherThanReportingNoUsers() async throws {
        let inventory = fixture(), connection = try XCTUnwrap(inventory.connections.first { $0.roots == [1] })
        let report = try await CableImpactScanner.scan(connection: connection, inventory: inventory, execute: { _, _, _ in .init(status: 2, output: "", errorOutput: "denied") })
        XCTAssertNil(report.diskUsers["disk"]); XCTAssertNil(report.sessions["network"])
        XCTAssertEqual(report.issues.count, 2)
        let partial = try await CableImpactScanner.scan(connection: connection, inventory: inventory, execute: { [tcp] _, args, _ in
            .init(status: 0, output: args.contains("-iTCP") ? tcp : "", errorOutput: "limited access")
        })
        XCTAssertFalse(partial.issues.isEmpty)
    }
    func testCancelledScanDoesNotReturnSuccessfulEmptyReport() async throws {
        let inventory = fixture(), connection = try XCTUnwrap(inventory.connections.first { $0.roots == [1] })
        actor ReadProgress {
            var started = false
            func mark() { started = true }
        }
        let progress = ReadProgress()
        let task = Task {
            try await CableImpactScanner.scan(connection: connection, inventory: inventory, execute: { _, _, _ in
                await progress.mark()
                try await Task.sleep(for: .seconds(10))
                return .init(status: 0, output: "", errorOutput: "")
            })
        }
        for _ in 0..<100 {
            if await progress.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await progress.started
        XCTAssertTrue(started, "Cancel while the production scanner is waiting for a reader")
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled scans cannot become success") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
