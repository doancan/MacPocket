import XCTest
@testable import MacPocketCore

final class WindowTabsTests: XCTestCase {
    private let frame = CGRect(x: 40, y: 80, width: 600, height: 420)
    private func window(_ id: String = "root", pid: Int32 = 7, number: UInt32 = 10, inactive: Bool = false, knownLaunch: Bool = true) -> SwitchableWindow {
        .init(id: id, processID: pid, application: "Editor", title: "Container", applicationURL: nil,
              minimized: inactive, hidden: inactive, fullScreen: inactive, frontmost: true, windowAccessible: true,
              canClose: true, canMinimize: true, canFullScreen: true, launchedAt: knownLaunch ? Date(timeIntervalSince1970: 10) : nil,
              lastFocusedAt: Date(timeIntervalSince1970: 50), windowID: number, frame: frame, displayID: 1, zOrder: 0, canResize: true)
    }
    private func bar(_ group: String = "g", anchor: String = "root", prefix: String = "", selected: Int = 0,
                     titles: [String] = ["Alpha", "Beta"]) -> WindowTabBar {
        WindowTabBar(groupID: group, anchorID: anchor, controls: titles.enumerated().map {
            .init(id: prefix + "button\($0.offset)", title: $0.element, selected: $0.offset == selected)
        })!
    }
    private func surfaces(pid: Int32 = 7, first: UInt32 = 10) -> [WindowTabSurface] {
        [.init(id: first, processID: pid, frame: frame, spaceIDs: [1]),
         .init(id: first + 1, processID: pid, frame: frame, spaceIDs: [])]
    }
    private func project(_ root: SwitchableWindow? = nil, bar: WindowTabBar? = nil) -> WindowTabProjection {
        WindowTabProjectionResolver.project([root ?? window()], surfaces: surfaces(), bars: [bar ?? self.bar()])
    }

    func testOnlySelectedControlReceivesVerifiedWindowIDAndActions() {
        let result = project()
        XCTAssertEqual(result.windows.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(result.windows.map(\.windowID), [10, nil])
        XCTAssertTrue(result.windows.allSatisfy(\.isRealWindow))
        XCTAssertEqual(result.windows.map(\.canCapturePreview), [true, false])
        XCTAssertEqual(result.windows.map(\.canClose), [true, false])
        XCTAssertEqual(result.windows.map(\.windowAccessible), [true, false])
        XCTAssertEqual(result.windows.map { $0.nativeTab?.ordinal }, [1, 2])
        XCTAssertEqual(result.windows.map { $0.nativeTab?.count }, [2, 2])
        XCTAssertEqual(result.bindings[result.windows[0].id]?.expectedWindowID, 10)
        XCTAssertNil(result.bindings[result.windows[1].id]?.expectedWindowID)
    }

    func testGroupDefaultPrefersSelectedControlAndSearchCanFindInactiveTab() {
        let cards = project(bar: bar(selected: 1)).windows
        var filter = WindowListFilter()
        XCTAssertEqual(WindowFiltering.apply(cards, filter: filter, order: .title).map(\.title), ["Beta"])
        XCTAssertEqual(WindowFiltering.apply(cards, filter: filter, search: "Alpha").map(\.title), ["Alpha"])
        filter.separateTabs = true
        XCTAssertEqual(WindowFiltering.apply(cards, filter: filter, order: .title).map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(WindowFiltering.apply(cards, order: .title).count, 2, "Tools/legacy detail API keeps separate records")
        filter.grouping = .onePerApplication
        XCTAssertEqual(WindowFiltering.apply(cards, filter: filter).count, 1)
        filter.windowless = .hide
        XCTAssertEqual(WindowFiltering.apply(cards, filter: filter, search: "Alpha").count, 1)
    }

    func testContainerSpaceAndVisibilityAreInheritedWithoutInventingBackgroundMembership() {
        var root = window(inactive: true)
        let space = WindowSpace(id: 3, ordinal: 2, displayIdentifier: "display", kind: .fullScreen, visible: false)
        root.spaceMembership = .init(spaces: [space])
        let cards = project(root).windows
        XCTAssertTrue(cards.allSatisfy { $0.minimized && $0.hidden && $0.fullScreen && $0.isOnAnotherSpace })
        XCTAssertTrue(cards.allSatisfy { $0.spaceMembership == root.spaceMembership && $0.displayID == 1 && $0.frame == frame })
        var filter = WindowListFilter()
        filter.separateTabs = true
        filter.spaceScope = .visible
        XCTAssertTrue(WindowFiltering.apply(cards, filter: filter).isEmpty)
        filter.spaceScope = .notVisible
        XCTAssertEqual(WindowFiltering.apply(cards, filter: filter).count, 2)
        filter.includeFullScreen = false
        XCTAssertTrue(WindowFiltering.apply(cards, filter: filter).isEmpty)
    }

    func testIdenticalAndEmptyTitlesDoNotBecomeSurfaceIdentifiers() {
        for titles in [["Same", "Same"], ["", ""]] {
            let result = project(bar: bar(titles: titles))
            XCTAssertEqual(result.windows.count, 2)
            XCTAssertEqual(Set(result.windows.map(\.id)).count, 2)
            XCTAssertNil(result.windows[1].windowID)
            XCTAssertEqual(result.bindings[result.windows[1].id]?.controlID, "button1")
        }
    }

    func testButtonIdentitySurvivesSelectionAndPreservesFocusHistory() {
        let first = project()
        let inactiveID = first.windows[1].id
        let focus = Date(timeIntervalSince1970: 90)
        let second = WindowTabProjectionResolver.project([window(number: 11)], surfaces: [
            .init(id: 10, processID: 7, frame: frame, spaceIDs: []),
            .init(id: 11, processID: 7, frame: frame, spaceIDs: [1])
        ], bars: [bar(selected: 1)], focusHistory: [inactiveID: focus])
        XCTAssertEqual(first.windows.map(\.id), second.windows.map(\.id))
        XCTAssertEqual(second.windows.map(\.windowID), [nil, 11])
        XCTAssertEqual(second.windows[1].lastFocusedAt, focus)
        XCTAssertEqual(second.observedFocus[inactiveID], Date(timeIntervalSince1970: 50))
        XCTAssertEqual(second.windows[0].nativeTab?.selected, false)
    }

    func testActivationFollowsExactControlAfterReorderAndRejectsReplacementOrRename() {
        let reordered = WindowTabBar(groupID: "g", anchorID: "root", controls: [
            .init(id: "button1", title: "Beta", selected: true), .init(id: "button0", title: "Alpha", selected: false)
        ])!
        XCTAssertEqual(WindowTabProjectionResolver.activationIndex(controlID: "button0", title: "Alpha", in: reordered), 1)
        XCTAssertNil(WindowTabProjectionResolver.activationIndex(controlID: "old-button", title: "Alpha", in: reordered))
        XCTAssertNil(WindowTabProjectionResolver.activationIndex(controlID: "button0", title: "Renamed", in: reordered))
    }

    func testOrdinaryInWindowTabsHaveNoPhysicalCorroboration() {
        let root = window()
        let activeOnly = [surfaces()[0]]
        let result = WindowTabProjectionResolver.project([root], surfaces: activeOnly, bars: [bar()])
        XCTAssertEqual(result.windows.map(\.id), [root.id])
        XCTAssertTrue(result.bindings.isEmpty)
    }

    func testUnknownOrAssignedBackgroundSpaceIsNeverProofOfInactiveTab() {
        for ids: Set<UInt64>? in [nil, [1], [2]] {
            let facts = [surfaces()[0], WindowTabSurface(id: 11, processID: 7, frame: frame, spaceIDs: ids)]
            XCTAssertTrue(WindowTabProjectionResolver.project([window()], surfaces: facts, bars: [bar()]).bindings.isEmpty)
        }
        let facts = [WindowTabSurface(id: 10, processID: 7, frame: frame, spaceIDs: []), surfaces()[1]]
        XCTAssertTrue(WindowTabProjectionResolver.project([window()], surfaces: facts, bars: [bar()]).bindings.isEmpty)
    }

    func testMismatchedFrameProcessOrSurfaceCountRejectsProjection() {
        let root = window()
        let variants: [[WindowTabSurface]] = [
            [surfaces()[0], .init(id: 11, processID: 8, frame: frame, spaceIDs: [])],
            [surfaces()[0], .init(id: 11, processID: 7, frame: frame.offsetBy(dx: 1, dy: 0), spaceIDs: [])],
            surfaces() + [.init(id: 12, processID: 7, frame: frame, spaceIDs: [])],
            surfaces() + [surfaces()[1]], surfaces() + [surfaces()[0]]
        ]
        for facts in variants {
            XCTAssertTrue(WindowTabProjectionResolver.project([root], surfaces: facts, bars: [bar()]).bindings.isEmpty)
        }
    }

    func testUnknownProcessIdentityOrMissingAnchorNeverGeneratesActionIDs() {
        let root = window(knownLaunch: false)
        XCTAssertTrue(project(root).bindings.isEmpty)
        XCTAssertTrue(project(bar: bar(anchor: "missing")).bindings.isEmpty)
        XCTAssertTrue(WindowTabProjectionResolver.project([window(), window()], surfaces: surfaces(), bars: [bar()]).bindings.isEmpty)
    }

    func testStackedGroupsUseCombinedPhysicalEvidenceWithoutCrossAssigningBackgroundIDs() {
        let roots = [window(), window("second", number: 20), window("raw-inactive", number: 11)]
        let facts = surfaces() + [WindowTabSurface(id: 20, processID: 7, frame: frame, spaceIDs: [1]),
                                  WindowTabSurface(id: 21, processID: 7, frame: frame, spaceIDs: [])]
        let bars = [bar(), bar("g2", anchor: "second", prefix: "second-")]
        let result = WindowTabProjectionResolver.project(roots, surfaces: facts, bars: bars)
        XCTAssertEqual(result.windows.count, 4)
        XCTAssertEqual(Set(result.windows.compactMap(\.windowID)), [10, 20])
        XCTAssertEqual(Set(result.windows.compactMap { $0.nativeTab?.groupID }).count, 2)
        let incomplete = WindowTabProjectionResolver.project(roots, surfaces: Array(facts.dropLast()), bars: bars)
        XCTAssertTrue(incomplete.bindings.isEmpty)
    }

    func testConflictingGroupsOrSharedControlsAreRejectedTogether() {
        let roots = [window(), window("second", number: 20)]
        let facts = surfaces() + [WindowTabSurface(id: 20, processID: 7, frame: frame, spaceIDs: [1]),
                                  WindowTabSurface(id: 21, processID: 7, frame: frame, spaceIDs: [])]
        for bars in [[bar(), bar()], [bar(), bar("g2", anchor: "second")],
                     [bar(), bar("g", anchor: "second", prefix: "second-")]] {
            XCTAssertTrue(WindowTabProjectionResolver.project(roots, surfaces: facts, bars: bars).bindings.isEmpty)
        }
    }

    func testRawGroupAndControlNamesAreScopedToProcessInstance() {
        let result = WindowTabProjectionResolver.project([window(), window("other", pid: 8, number: 20)],
            surfaces: surfaces() + surfaces(pid: 8, first: 20), bars: [bar(), bar(anchor: "other")])
        XCTAssertEqual(result.windows.count, 4)
        XCTAssertEqual(Set(result.windows.map(\.id)).count, 4)
        XCTAssertEqual(Set(result.windows.compactMap { $0.nativeTab?.groupID }).count, 2)
    }

    func testBackgroundTabIsNeverCapturedEvenWhenSelectedInSwitcher() {
        let cards = project().windows
        let targets = WindowThumbnailPlan.targets(cards, selection: cards[1].id, visibleIDs: Set(cards.map(\.id)))
        XCTAssertEqual(targets.map(\.windowID), [10])
    }

    func testCreationObservationBelongsToVerifiedControlAndPersistsForInactiveTab() {
        var root = window()
        let observation = WindowCreationObservation(sessionID: UUID(), sequence: 8, observedAt: .now)
        root.creationObservation = observation
        let first = project(root)
        XCTAssertEqual(first.windows[0].creationObservation, observation)
        XCTAssertNil(first.windows[1].creationObservation, "The anchor's creation date must not be copied to an unknown background tab")
        let changed = WindowTabProjectionResolver.project([window(number: 11)], surfaces: [
            .init(id: 10, processID: 7, frame: frame, spaceIDs: []),
            .init(id: 11, processID: 7, frame: frame, spaceIDs: [1])
        ], bars: [bar(selected: 1)], creationHistory: [first.windows[0].id: observation])
        XCTAssertEqual(changed.windows[0].creationObservation, observation)
        XCTAssertNil(changed.windows[1].creationObservation)
    }

    func testSeparateTabsDefaultsOffAndRoundTrips() throws {
        XCTAssertFalse(try JSONDecoder().decode(WindowListFilter.self, from: Data("{}".utf8)).separateTabs)
        var filter = WindowListFilter()
        filter.separateTabs = true
        XCTAssertTrue(try JSONDecoder().decode(WindowListFilter.self, from: JSONEncoder().encode(filter)).separateTabs)
    }

    func testMalformedBarsAreRejectedBeforePublication() {
        let one = WindowTabControl(id: "a", title: "A", selected: true)
        XCTAssertNil(WindowTabBar(groupID: "", anchorID: "root", controls: [one, one]))
        XCTAssertNil(WindowTabBar(groupID: "g", anchorID: "", controls: [one, one]))
        XCTAssertNil(WindowTabBar(groupID: "g", anchorID: "root", controls: [one]))
        XCTAssertNil(WindowTabBar(groupID: "g", anchorID: "root", controls: [one, one]))
        XCTAssertNil(WindowTabBar(groupID: "g", anchorID: "root", controls: [one, .init(id: "b", title: "B", selected: true)]))
        XCTAssertNil(WindowTabBar(groupID: "g", anchorID: "root", controls: [.init(id: "a", title: "A", selected: false), .init(id: "b", title: "B", selected: false)]))
    }
}
