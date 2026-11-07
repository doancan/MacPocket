import XCTest
@testable import MacPocketCore

private final class SpaceQueryFixture: WindowSpaceQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private let topologyValues: [CFArray]
    private let membershipValues: [UInt32: CFArray]
    private var topologyIndex = 0
    private var queries: [UInt32] = []
    let connection: UInt32
    init(topologies: [CFArray], memberships: [UInt32: CFArray], connection: UInt32 = 1) {
        self.topologyValues = topologies; self.membershipValues = memberships; self.connection = connection
    }
    func connectionID() -> UInt32 { connection }
    func copyTopology(connection: UInt32) -> CFArray? {
        lock.withLock {
            guard !topologyValues.isEmpty else { return nil }
            let result = topologyValues[min(topologyIndex, topologyValues.count - 1)]
            topologyIndex += 1; return result
        }
    }
    func copyMembership(connection: UInt32, windowID: UInt32) -> CFArray? {
        lock.withLock { queries.append(windowID); return membershipValues[windowID] }
    }
    var queriedIDs: [UInt32] { lock.withLock { queries } }
}

final class WindowSpacesTests: XCTestCase {
    private func display(_ name: String, ids: [UInt64], current: UInt64, fullScreen: Set<UInt64> = []) -> [String: Any] {
        ["Display Identifier": name,
         "Current Space": ["id64": NSNumber(value: current)],
         "Spaces": ids.map { ["id64": NSNumber(value: $0), "type": NSNumber(value: fullScreen.contains($0) ? 4 : 0)] }]
    }
    private func topology(_ displays: [[String: Any]]) throws -> SpaceTopology {
        try XCTUnwrap(SpaceTopology.parse(displays as CFArray))
    }
    private func window(_ id: String, membership: WindowSpaceMembership? = nil, minimized: Bool = false,
                        hidden: Bool = false, inferredOther: Bool = false, z: Int? = nil, focus: TimeInterval? = nil) -> SwitchableWindow {
        .init(id: id, processID: 1, application: "Fixture", title: id, applicationURL: nil, minimized: minimized, hidden: hidden,
              fullScreen: false, frontmost: false, windowAccessible: true, canClose: true, canMinimize: true, canFullScreen: true,
              launchedAt: nil, lastFocusedAt: focus.map(Date.init(timeIntervalSince1970:)), otherSpace: inferredOther, zOrder: z,
              spaceMembership: membership)
    }

    func testIndependentDisplaysExposeAllVisibleSpacesAndStableMissionControlOrder() throws {
        let value = try topology([display("Display A", ids: [11, 12], current: 12),
                                  display("Display B", ids: [91, 92], current: 91, fullScreen: [92])])
        XCTAssertEqual(value.spaces.map(\.id), [11, 12, 91, 92])
        XCTAssertEqual(value.spaces.map(\.ordinal), [1, 2, 3, 4])
        XCTAssertEqual(value.spaces.filter(\.visible).map(\.id), [12, 91])
        XCTAssertEqual(value.spaces.last?.kind, .fullScreen)
        XCTAssertEqual(value.spaces.last?.displayIdentifier, "Display B")
        let shared = try topology([display("Main", ids: [11, 12], current: 12)])
        XCTAssertEqual(shared.spaces.map(\.id), [11, 12])
    }

    func testSharedIDsAcrossDisplaysAreDeduplicatedAndVisibilityIsTheirUnion() throws {
        let value = try topology([display("A", ids: [11, 12], current: 11), display("B", ids: [11, 12], current: 12)])
        XCTAssertEqual(value.spaces.map(\.id), [11, 12])
        XCTAssertEqual(value.spaces.map(\.ordinal), [1, 2])
        XCTAssertTrue(value.spaces.allSatisfy(\.visible))
    }

    func testMalformedOrTransitionalTopologyIsUnknownRatherThanAGuessedDesktop() {
        let invalid: [CFArray] = [[], [["Spaces": []]], [display("A", ids: [11], current: 12)],
                                  [display("", ids: [11], current: 11)], [display("A", ids: [11, 11], current: 11)],
                                  [["Display Identifier": "A", "Current Space": ["id64": true], "Spaces": [["id64": true]]]],
                                  [["Display Identifier": "A", "Current Space": ["id64": -1], "Spaces": [["id64": -1]]]]]
            .map { $0 as CFArray }
        for raw in invalid { XCTAssertNil(SpaceTopology.parse(raw)) }
        XCTAssertNil(SpaceTopology.ids([NSNumber(value: -1)] as CFArray))
        XCTAssertNil(SpaceTopology.ids([true] as CFArray))
        XCTAssertNil(SpaceTopology.ids(["11"] as CFArray))
    }

    func testMembershipPreservesFullWidthIDsAndDoesNotInventUnknownOrdinals() throws {
        let wide = UInt64.max - 1
        let topology = try topology([display("A", ids: [11, wide], current: 11)])
        let snapshot = WindowSpaceSnapshot(spaces: topology.spaces, memberships: [7: [wide], 8: [11, 500], 9: []])
        XCTAssertEqual(snapshot.membership(for: 7)?.spaces.first?.id, wide)
        XCTAssertEqual(snapshot.membership(for: 7)?.isVisible, false)
        XCTAssertEqual(snapshot.membership(for: 8)?.unknownIDs, [500])
        XCTAssertEqual(snapshot.membership(for: 8)?.isVisible, true, "One known visible membership is sufficient")
        XCTAssertNil(snapshot.membership(for: 8)?.firstOrdinal, "Incomplete membership cannot prove the first desktop")
        XCTAssertNil(snapshot.membership(for: 9)); XCTAssertNil(snapshot.membership(for: 10))
        XCTAssertEqual(SpaceTopology.ids([NSNumber(value: wide), NSNumber(value: 11)] as CFArray), [wide, 11])
    }

    func testMinimizedAndHiddenWindowsUseMembershipInsteadOfOnscreenGuess() throws {
        let topology = try topology([display("A", ids: [11, 12], current: 11)])
        let snapshot = WindowSpaceSnapshot(spaces: topology.spaces, memberships: [1: [11], 2: [12]])
        let current = snapshot.membership(for: 1), other = snapshot.membership(for: 2)
        let windows = [window("minimized-current", membership: current, minimized: true, inferredOther: true),
                       window("hidden-current", membership: current, hidden: true),
                       window("minimized-other", membership: other, minimized: true), window("unknown")]
        var filter = WindowListFilter(); filter.spaceScope = .visible
        XCTAssertEqual(WindowFiltering.apply(windows, filter: filter).map(\.id), ["minimized-current", "hidden-current", "unknown"])
        filter.spaceScope = .notVisible
        XCTAssertEqual(WindowFiltering.apply(windows, filter: filter).map(\.id), ["minimized-other", "unknown"])
        XCTAssertFalse(windows[0].isOnAnotherSpace); XCTAssertTrue(windows[2].isOnAnotherSpace)
    }

    func testStickyWindowIsVisibleOnAnyCurrentDesktopAndUnknownMembershipFallsBack() throws {
        let topology = try topology([display("A", ids: [11, 12], current: 11), display("B", ids: [91], current: 91)])
        let snapshot = WindowSpaceSnapshot(spaces: topology.spaces, memberships: [1: [12, 91], 2: [999]])
        XCTAssertEqual(snapshot.membership(for: 1)?.isVisible, true)
        XCTAssertNil(snapshot.membership(for: 2)?.isVisible)
        XCTAssertNil(snapshot.membership(for: 2)?.firstOrdinal)
        var filter = WindowListFilter(); filter.spaceScope = .notVisible
        let input = [window("sticky", membership: snapshot.membership(for: 1)), window("unknown", membership: snapshot.membership(for: 2)),
                     window("inferred-other", inferredOther: true), window("on-screen", z: 1)]
        XCTAssertEqual(WindowFiltering.apply(input, filter: filter).map(\.id), ["unknown", "inferred-other"])
    }

    func testSpaceOrderSortsWithinDesktopByMRUAndKeepsUnknownAtEnd() throws {
        let topology = try topology([display("A", ids: [11, 12], current: 11)])
        let snapshot = WindowSpaceSnapshot(spaces: topology.spaces, memberships: [1: [11], 2: [12]])
        let first = snapshot.membership(for: 1), second = snapshot.membership(for: 2)
        let input = [window("unknown", focus: 100), window("second", membership: second, focus: 50),
                     window("first-old", membership: first, focus: 10), window("first-new", membership: first, focus: 20)]
        XCTAssertEqual(WindowFiltering.apply(input, order: .space).map(\.id), ["first-new", "first-old", "second", "unknown"])
        var filter = WindowListFilter(); filter.minimized = .atEnd
        let withMinimized = input + [window("first-minimized", membership: first, minimized: true, focus: 99)]
        XCTAssertEqual(WindowFiltering.apply(withMinimized, filter: filter, order: .space).last?.id, "first-minimized")
        XCTAssertEqual(try JSONDecoder().decode(WindowSortOrder.self, from: Data(#""space""#.utf8)), .space)
    }

    func testUnavailableSnapshotDoesNotEraseTheFallbackOrClaimFullscreenWindowState() throws {
        let unavailable = WindowSpaceSnapshot(memberships: [1: [11]], partial: true)
        XCTAssertFalse(unavailable.available); XCTAssertTrue(unavailable.partial); XCTAssertNil(unavailable.membership(for: 1))
        let topology = try topology([display("A", ids: [11], current: 11, fullScreen: [11])])
        let membership = WindowSpaceSnapshot(spaces: topology.spaces, memberships: [1: [11]]).membership(for: 1)
        let auxiliaryWindow = window("auxiliary", membership: membership)
        XCTAssertEqual(auxiliaryWindow.spaceMembership?.spaces.first?.kind, .fullScreen)
        XCTAssertFalse(auxiliaryWindow.fullScreen, "Being on a fullscreen Space does not prove the window itself is fullscreen")
    }

    func testProviderUsesOneQueryPerUniqueWindowAndPreservesEmptyVersusFailedReads() async {
        let raw = [display("A", ids: [11, 12], current: 11)] as CFArray
        let backend = SpaceQueryFixture(topologies: [raw], memberships: [1: [NSNumber(value: 11)] as CFArray,
                                                                      2: [] as CFArray, 4: ["malformed"] as CFArray])
        let provider = WindowSpaceProvider(backend: backend)
        let value = await provider.snapshot(windowIDs: [0, 1, 1, 2, 3, 4])
        XCTAssertTrue(value.available); XCTAssertTrue(value.partial)
        XCTAssertEqual(backend.queriedIDs, [1, 2, 3, 4])
        XCTAssertEqual(value.membership(for: 1)?.isVisible, true)
        XCTAssertEqual(value.memberships[2], [])
        XCTAssertNil(value.memberships[3]); XCTAssertNil(value.memberships[4])
    }

    func testProviderDiscardsMixedTopologyDuringARealisticSpaceTransition() async {
        let before = [display("A", ids: [11, 12], current: 11)] as CFArray
        let after = [display("A", ids: [11, 12], current: 12)] as CFArray
        let backend = SpaceQueryFixture(topologies: [before, after], memberships: [1: [NSNumber(value: 11)] as CFArray])
        let value = await WindowSpaceProvider(backend: backend).snapshot(windowIDs: [1])
        XCTAssertFalse(value.available); XCTAssertTrue(value.partial)
        XCTAssertTrue(value.memberships.isEmpty, "A mixed snapshot must not mark the old desktop visible")
    }

    func testProviderBudgetReturnsUnknownMembershipWithoutInventingIt() async {
        let raw = [display("A", ids: [11], current: 11)] as CFArray
        let backend = SpaceQueryFixture(topologies: [raw], memberships: [1: [NSNumber(value: 11)] as CFArray])
        let value = await WindowSpaceProvider(backend: backend, queryBudget: .zero).snapshot(windowIDs: [1])
        XCTAssertTrue(value.available); XCTAssertTrue(value.partial)
        XCTAssertTrue(backend.queriedIDs.isEmpty); XCTAssertNil(value.membership(for: 1))
    }

    func testMissingSymbolsConnectionOrMalformedBackendLeaveExistingFilteringAvailable() async {
        let absent = await WindowSpaceProvider(backend: nil).snapshot(windowIDs: [1])
        XCTAssertFalse(absent.available); XCTAssertTrue(absent.memberships.isEmpty)
        let raw = [display("A", ids: [11], current: 11)] as CFArray
        let disconnected = SpaceQueryFixture(topologies: [raw], memberships: [:], connection: 0)
        let failed = await WindowSpaceProvider(backend: disconnected).snapshot(windowIDs: [1])
        XCTAssertFalse(failed.available); XCTAssertTrue(disconnected.queriedIDs.isEmpty)
        let malformed = SpaceQueryFixture(topologies: [[] as CFArray], memberships: [:])
        let malformedResult = await WindowSpaceProvider(backend: malformed).snapshot(windowIDs: [1])
        XCTAssertFalse(malformedResult.available); XCTAssertTrue(malformed.queriedIDs.isEmpty)
        var filter = WindowListFilter(); filter.spaceScope = .visible
        XCTAssertEqual(WindowFiltering.apply([window("old-current"), window("old-other", inferredOther: true)], filter: filter).map(\.id), ["old-current"])
    }
}
