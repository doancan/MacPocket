import XCTest
@testable import MacPocketCore

final class SwitcherActionBindingTests: XCTestCase {
    func testDefaultsAreValidAndIgnoreHeldOpeningModifiers() {
        XCTAssertTrue(SwitcherActionBindings.problems(SwitcherActionBinding.defaults).isEmpty)
        XCTAssertEqual(SwitcherActionBindings.action(for: 13, modifiers: [.option, .command], shift: false, held: .option,
                                                    isSearching: false, bindings: SwitcherActionBinding.defaults), .close)
        XCTAssertEqual(SwitcherActionBindings.action(for: 13, modifiers: .command, shift: false, held: .command,
                                                   isSearching: false, bindings: SwitcherActionBinding.defaults),.close)
    }

    func testCommandHeldActionsPreserveSearchTypingAndExplicitBareActionPriority() {
        let close = SwitcherActionBinding.defaults
        XCTAssertNil(SwitcherActionBindings.action(for: 13,modifiers: .command,shift: false,held: .command,isSearching: true,bindings: close))
        let bindings = close + [.init(action: .hide,keyCode: 13)]
        XCTAssertEqual(SwitcherActionBindings.action(for: 13,modifiers: .command,shift: false,held: .command,isSearching: false,bindings: bindings),.hide)
        XCTAssertEqual(SwitcherActionBindings.action(for: 13,modifiers: .command,shift: false,held: [],isSearching: true,bindings: close),.close)
    }

    func testCustomActionReplacesOldKeyRatherThanAddingAlias() {
        var bindings = SwitcherActionBinding.defaults
        let index = bindings.firstIndex { $0.action == .close }!
        bindings[index].keyCode = 2 // D
        XCTAssertNil(SwitcherActionBindings.action(for: 13, modifiers: .command, shift: false, held: [], isSearching: false, bindings: bindings))
        XCTAssertEqual(SwitcherActionBindings.action(for: 2, modifiers: .command, shift: false, held: [], isSearching: false, bindings: bindings), .close)
        bindings[index].keyCode = nil
        XCTAssertNil(SwitcherActionBindings.action(for: 2, modifiers: .command, shift: false, held: [], isSearching: false, bindings: bindings))
    }

    func testBareLettersStayTextDuringSearchWhileEnterCanChoose() {
        let close = SwitcherActionBinding(action: .close, keyCode: 13)
        XCTAssertEqual(SwitcherActionBindings.action(for: 13, modifiers: .option, shift: false, held: .option,
                                                    isSearching: false, bindings: [close]), .close)
        XCTAssertNil(SwitcherActionBindings.action(for: 13, modifiers: .option, shift: false, held: .option,
                                                   isSearching: true, bindings: [close]))
        XCTAssertEqual(SwitcherActionBindings.action(for: 36, modifiers: [], shift: false, held: [],
                                                    isSearching: true, bindings: SwitcherActionBinding.defaults), .choose)
        XCTAssertEqual(SwitcherActionBindings.action(for: 1, modifiers: .command, shift: false, held: [],
                                                    isSearching: false, bindings: SwitcherActionBinding.defaults), .search)
    }

    func testConflictsAndReservedNavigationAreRejected() {
        var bindings = SwitcherActionBinding.defaults
        bindings[0] = .init(action: .choose, keyCode: 13, modifiers: .command)
        XCTAssertFalse(SwitcherActionBindings.problems(bindings).isEmpty)
        XCTAssertFalse(SwitcherActionBindings.problems([.init(action: .close, keyCode: 48)]).isEmpty)
        XCTAssertFalse(SwitcherActionBindings.problems([.init(action: .close, keyCode: 53)]).isEmpty)
        XCTAssertFalse(SwitcherActionBindings.problems([.init(action: .close, keyCode: 13, modifiers: .init(rawValue: 128))]).isEmpty)
    }

    func testSelectionKeyMustRemainReachableWhileEnteringSearchText() {
        for code: UInt16 in [0, 49, 51] {
            XCTAssertFalse(SwitcherActionBindings.problems([.init(action: .choose, keyCode: code)]).isEmpty)
        }
        let binding = SwitcherActionBinding(action: .choose, keyCode: 0, modifiers: .control)
        XCTAssertTrue(SwitcherActionBindings.problems([binding]).isEmpty)
        XCTAssertEqual(SwitcherActionBindings.action(for: 0, modifiers: .control, shift: false, held: [],
                                                    isSearching: true, bindings: [binding]), .choose)
    }

    func testDisabledBindingAndShiftRoundTripWithoutResettingOthers() throws {
        let suite = "MacPocket-action-bindings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var bindings = SwitcherActionBinding.defaults
        let index = try XCTUnwrap(bindings.firstIndex { $0.action == .close })
        bindings[index].keyCode = nil
        SwitcherActionBindings.save(bindings, defaults)
        XCTAssertEqual(SwitcherActionBindings.load(defaults), bindings)
        let previous = defaults.data(forKey: SwitcherActionBindings.key)
        bindings[0] = .init(action: .choose, keyCode: 46, modifiers: .command)
        SwitcherActionBindings.save(bindings, defaults)
        XCTAssertEqual(defaults.data(forKey: SwitcherActionBindings.key), previous)
    }
}
