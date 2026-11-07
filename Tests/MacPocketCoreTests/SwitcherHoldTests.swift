import XCTest
@testable import MacPocketCore

final class SwitcherHoldTests: XCTestCase {
    func testReplacingOpeningChordPreservesIndependentProfileAndValidHoldOwnership() {
        var original = SwitcherShortcut(keyCode: 48,modifiers: [.control,.option],releaseBehavior: .search,holdModifiers: .option)
        original.filter.applicationScope = .other;original.presentation.style = .titles
        let command = original.replacingOpeningChord(keyCode: 48,modifiers: .command)
        XCTAssertEqual(command.id,original.id);XCTAssertEqual(command.filter,original.filter)
        XCTAssertEqual(command.presentation,original.presentation);XCTAssertEqual(command.releaseBehavior,.search)
        XCTAssertNil(command.holdModifiers);XCTAssertEqual(command.effectiveHoldModifiers,.command)
        let retained = original.replacingOpeningChord(keyCode: 49,modifiers: [.command,.option])
        XCTAssertEqual(retained.holdModifiers,.option);XCTAssertEqual(retained.keyCode,49)
        XCTAssertTrue(SwitcherShortcutValidation.problems([command]).isEmpty)
    }
    func testOldArchivesKeepAllOpeningModifiersWithoutAddingAnOverride() throws {
        let legacy = Data(#"{"keyCode":48,"modifiers":3,"releaseToChoose":true}"#.utf8)
        let decoded = try JSONDecoder().decode(SwitcherShortcut.self,from: legacy)
        XCTAssertNil(decoded.holdModifiers);XCTAssertEqual(decoded.effectiveHoldModifiers,[.control,.option])
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String:Any])
        XCTAssertNil(encoded["holdModifiers"])
    }
    func testExplicitHoldSetSurvivesStoreAndJSONWithAllOtherProfileValues() throws {
        var shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: [.control,.option],releaseBehavior: .search,holdModifiers: .option)
        shortcut.filter.includeHidden = false;shortcut.presentation.showBadges = false
        let data = try JSONEncoder().encode(shortcut),decoded = try JSONDecoder().decode(SwitcherShortcut.self,from: data)
        XCTAssertEqual(decoded,shortcut);XCTAssertEqual(decoded.effectiveHoldModifiers,.option)
        let name = "SwitcherHoldTests."+UUID().uuidString,defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        SwitcherShortcutStore.save([shortcut],defaults);XCTAssertEqual(SwitcherShortcutStore.load(defaults),[shortcut])
    }
    func testEveryNonemptySubsetIsValidAndEmptyOutsideOrUnknownFlagsAreRejected() {
        for raw in 1...7 {
            let opening = SwitcherModifiers(rawValue: raw)
            for heldRaw in 0...15 {
                let held = SwitcherModifiers(rawValue: heldRaw)
                let shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: opening,holdModifiers: held)
                let expected = heldRaw > 0 && heldRaw & ~7 == 0 && opening.isSuperset(of: held)
                XCTAssertEqual(SwitcherShortcutValidation.problems([shortcut]).isEmpty,expected,"\(raw)/\(heldRaw)")
            }
        }
    }
    func testDefaultTracksEditedChordButExplicitSetKeepsItsIdentity() {
        var automatic = SwitcherShortcut(keyCode: SwitcherKeys.grave,modifiers: .option)
        var fixed = automatic;fixed.holdModifiers = .option
        automatic.modifiers.insert(.control);fixed.modifiers.insert(.control)
        XCTAssertEqual(automatic.effectiveHoldModifiers,[.control,.option]);XCTAssertEqual(fixed.effectiveHoldModifiers,.option)
        XCTAssertTrue(SwitcherShortcutValidation.problems([fixed]).isEmpty)
    }
    func testPickerChoicesContainAllAndOnlyNonemptyAllowedCombinations() {
        for raw in 1...7 {
            let shortcut = SwitcherShortcut(keyCode: SwitcherKeys.grave,modifiers: .init(rawValue: raw))
            let expected = Set((1...7).filter { $0 & raw == $0 })
            XCTAssertEqual(Set(shortcut.holdModifierChoices.map(\.rawValue)),expected)
        }
    }
    func testHoldingOnlyOptionLeavesCommandAvailableForActions() {
        let command = SwitcherPanelInput.command(keyCode: 13,characters: "w",modifiers: [.option,.command],shift: false,held: .option,
            isSearching: false,options: .init(),bindings: SwitcherActionBinding.defaults)
        XCTAssertEqual(command,.action(.close))
        XCTAssertEqual(SwitcherPanelInput.command(keyCode: 48,characters: "",modifiers: .option,shift: true,held: .option,
            isSearching: false,options: .init(),bindings: SwitcherActionBinding.defaults),.action(.previous))
    }
    func testTransferPreservesExplicitHoldBytesAndRejectsInvalidHoldBeforeApplying() throws {
        let name = "SwitcherHoldTests.Transfer."+UUID().uuidString,defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let profile = SwitcherShortcut(keyCode: 48,modifiers: [.control,.option],holdModifiers: .option)
        let bytes = try JSONEncoder().encode([profile]),archive = try SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: bytes])
        try SettingsTransfer.importAndApply(archive,to: defaults,domain: name)
        XCTAssertEqual(defaults.data(forKey: SwitcherShortcutStore.key),bytes)
        let before = defaults.persistentDomain(forName: name)!
        for held: SwitcherModifiers in [[],.command,.init(rawValue: 8)] {
            var invalid = profile;invalid.holdModifiers = held
            let bad = try SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: JSONEncoder().encode([invalid]),"MacPocket.appearance": "changed"])
            XCTAssertThrowsError(try SettingsTransfer.importAndApply(bad,to: defaults,domain: name))
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: name)!))
        }
    }
}
