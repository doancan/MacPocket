import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class SettingsTransferIntegrityTests: XCTestCase {
    private func defaults() -> (UserDefaults,String) {
        let store = temporaryDefaultsStore()
        return (store.defaults,store.suiteName)
    }
    private func file(_ values: [String:Any],version: Any = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["format": SettingsTransfer.format,"version": version,"values": values])
    }
    private func rejectWithoutChanges(_ data: Data) throws {
        let (d,name) = defaults()
        d.set("dark",forKey: "MacPocket.appearance")
        d.set(false,forKey: "switcher.globalEnabled")
        d.set(["en"],forKey: "AppleLanguages")
        let original = d.persistentDomain(forName: name)!
        XCTAssertThrowsError(try SettingsTransfer.importAndApply(data,to: d,domain: name))
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: d.persistentDomain(forName: name)!))
    }
    func testAllNineShortcutsActionsAndConditionalExceptionsRoundTripWithoutReencoding() throws {
        let codes: [UInt16] = [48,50,49,122,120,99,118,96,97]
        var shortcuts = codes.map { SwitcherShortcut(keyCode: $0,modifiers: .option) }
        shortcuts[0].releaseBehavior = .search
        shortcuts[0].filter.minimized = .atEnd
        shortcuts[0].filter.separateTabs = true
        shortcuts[0].presentation.showBadges = false
        shortcuts[0].presentation.style = .titles
        var bindings = SwitcherActionBinding.defaults
        bindings[4].keyCode = 7
        let rules = [SwitcherExceptionRule(target: .bundlePrefix,value: "org.example.",visibility: .titleContains,titlePatterns: ["Draft","[Sensitive]"],shortcuts: .fullscreen)]
        let shortcutData = try JSONEncoder().encode(shortcuts),bindingData = try JSONEncoder().encode(bindings),ruleData = try JSONEncoder().encode(rules)
        let data = try SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: shortcutData,SwitcherActionBindings.key: bindingData,
            SwitcherExceptionStore.key: ruleData,"switcher.gestureFingers": 4,"switcher.gestureAxis": "vertical","switcher.gestureHaptics": true,
            SwitcherCursorPolicy.key: "differentDisplay","switcher.future": ["value": "keep"]])
        let (d,name) = defaults()
        try SettingsTransfer.importAndApply(data,to: d,domain: name)
        XCTAssertEqual(d.data(forKey: SwitcherShortcutStore.key),shortcutData)
        XCTAssertEqual(d.data(forKey: SwitcherActionBindings.key),bindingData)
        XCTAssertEqual(d.data(forKey: SwitcherExceptionStore.key),ruleData)
        XCTAssertEqual(SwitcherShortcutStore.load(d),shortcuts)
        XCTAssertEqual(SwitcherActionBindings.load(d),bindings)
        XCTAssertEqual(SwitcherExceptionStore.load(d).rules,rules)
        XCTAssertEqual(SwitcherGestureOptions.load(d),.init(fingers: 4,axis: .vertical,haptics: true))
        XCTAssertEqual(SwitcherCursorPolicy.load(d),.differentDisplay)
        XCTAssertEqual(d.dictionary(forKey: "switcher.future")?["value"] as? String,"keep")
    }
    func testCorruptDataWrapperCannotSilentlyDeleteOtherSettings() throws {
        try rejectWithoutChanges(file(["MacPocket.appearance": "light","switcher.shortcuts.v2": ["$data": "%%%"]]))
        try rejectWithoutChanges(file(["MacPocket.appearance": "light","MacPocket.payload": ["$data": 123]]))
    }
    func testNullOrNestedInvalidValueRejectsWholeImport() throws {
        for bad: Any in [NSNull(),["valid",NSNull()],["a": 1,"b": NSNull()]] {
            try rejectWithoutChanges(file(["MacPocket.appearance": "light","MacPocket.bad": bad]))
        }
    }
    func testMalformedShortcutJSONIsNotImportedAsAnOpaqueSuccessfulSetting() throws {
        let data = try SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: Data("not json".utf8),"MacPocket.appearance": "light"])
        try rejectWithoutChanges(data)
    }
    func testDuplicateMissingShortcutIDsAndTooManyShortcutsAreRejected() throws {
        try rejectWithoutChanges(SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: Data(#"[{"keyCode":48,"modifiers":2}]"#.utf8)]))
        let first = SwitcherShortcut.defaultOptionTab
        var second = first
        second.keyCode = SwitcherKeys.grave
        for list in [[first,second],Array(repeating: first,count: 10),[]] {
            let data = try SettingsTransfer.exportData(from: [SwitcherShortcutStore.key: JSONEncoder().encode(list)])
            try rejectWithoutChanges(data)
        }
    }
    func testConflictingActionBindingsPreserveExistingSettings() throws {
        var bindings = SwitcherActionBinding.defaults
        bindings.append(bindings[0])
        try rejectWithoutChanges(SettingsTransfer.exportData(from: [SwitcherActionBindings.key: JSONEncoder().encode(bindings)]))
        let partial = [SwitcherActionBinding(action: .close,keyCode: 46,modifiers: .command)]
        try rejectWithoutChanges(SettingsTransfer.exportData(from: [SwitcherActionBindings.key: JSONEncoder().encode(partial)]))
    }
    func testInvalidExceptionRuleCannotReplaceExistingSettings() throws {
        let rule = SwitcherExceptionRule(target: .applicationPath,value: "relative.app",visibility: .alwaysHide)
        try rejectWithoutChanges(SettingsTransfer.exportData(from: [SwitcherExceptionStore.key: JSONEncoder().encode([rule])]))
    }
    func testBooleanFractionalAndFutureFormatVersionsDoNotApply() throws {
        for version: Any in [true,1.5,9] { try rejectWithoutChanges(file(["MacPocket.appearance": "light"],version: version)) }
    }
    func testImportFileReadingIsBoundedBeforeJSONParsing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let valid = try file(["MacPocket.appearance": "dark"])
        try valid.write(to: url)
        XCTAssertEqual(try SettingsTransfer.readImportData(from: url),valid)
        try Data(repeating: 32,count: SettingsTransfer.maximumFileBytes+1).write(to: url)
        XCTAssertThrowsError(try SettingsTransfer.readImportData(from: url)) { XCTAssertEqual($0 as? SettingsTransferError,.tooLarge) }
        XCTAssertThrowsError(try SettingsTransfer.importValues(from: Data(repeating: 32,count: SettingsTransfer.maximumFileBytes+1))) { XCTAssertEqual($0 as? SettingsTransferError,.tooLarge) }
    }
    func testForeignInvalidValuesAreIgnoredAndUnrelatedDomainValuesSurviveReplacement() throws {
        let (d,name) = defaults()
        d.set("keep",forKey: "NSWindow Frame main")
        d.set(["en"],forKey: "AppleLanguages")
        d.set(1,forKey: "MacPocket.old")
        let data = try file(["switcher.style": "icons","MacPocket.appearance": "dark","OtherApp.bad": ["$data": "%%%"]])
        try SettingsTransfer.importAndApply(data,to: d,domain: name)
        XCTAssertEqual(d.string(forKey: "switcher.style"),"icons")
        XCTAssertNil(d.object(forKey: "MacPocket.old"))
        XCTAssertEqual(d.string(forKey: "NSWindow Frame main"),"keep")
        XCTAssertEqual(d.stringArray(forKey: "AppleLanguages"),["en"])
        XCTAssertNil(d.object(forKey: "OtherApp.bad"))
    }
    func testDisabledGlobalShortcutSurvivesMissingOrFalseFirstRunMarker() throws {
        for marker: Bool? in [nil,false] {
            let (d,name) = defaults()
            var values: [String:Any] = ["switcher.globalEnabled": false]
            if let marker { values["switcher.cardOverlayConfigured"] = marker }
            try SettingsTransfer.importAndApply(file(values),to: d,domain: name)
            XCTAssertFalse(d.bool(forKey: "switcher.globalEnabled"))
            XCTAssertTrue(d.bool(forKey: "switcher.cardOverlayConfigured"))
        }
    }
    func testDateAndBinaryValuesRoundTripButMalformedDatesReject() throws {
        let date = Date(timeIntervalSince1970: 1234.5),raw = Data([0,255,1])
        let values = try SettingsTransfer.importValues(from: SettingsTransfer.exportData(from: ["MacPocket.date": date,"MacPocket.array": [date,raw]]))
        XCTAssertEqual(values["MacPocket.date"] as? Date,date)
        let array = try XCTUnwrap(values["MacPocket.array"] as? [Any])
        XCTAssertEqual(array[0] as? Date,date)
        XCTAssertEqual(array[1] as? Data,raw)
        try rejectWithoutChanges(file(["MacPocket.date": ["$date": true]]))
    }
}
