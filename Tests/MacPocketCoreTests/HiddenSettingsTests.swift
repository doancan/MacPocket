import XCTest
@testable import MacPocketCore

/// In-memory stand-in for CFPreferences.
private final class MemoryStore: HiddenSettingsStore, @unchecked Sendable {
    var values: [String: Any] = [:]
    var failingKeys: Set<String> = []
    private let lock = NSLock()

    private func slot(_ key: String, _ domain: HiddenSettingDomain) -> String { domain.rawValue + "/" + key }

    func read(_ key: String, domain: HiddenSettingDomain) -> Any? {
        lock.withLock { values[slot(key, domain)] }
    }

    func write(_ value: HiddenSettingValue?, key: String, domain: HiddenSettingDomain) -> Bool {
        lock.withLock {
            guard !failingKeys.contains(key) else { return false }
            switch value {
            case let .bool(flag)?: values[slot(key, domain)] = NSNumber(value: flag)
            case let .number(number)?: values[slot(key, domain)] = NSNumber(value: number)
            case let .text(text)?: values[slot(key, domain)] = text
            case nil: values[slot(key, domain)] = nil
            }
            return true
        }
    }
}

private actor RecordingRestarter: HiddenSettingsRestarting {
    private(set) var restarted: [HiddenSettingRestart] = []
    var failing: Set<HiddenSettingRestart> = []

    func fail(_ target: HiddenSettingRestart) { failing.insert(target) }

    func restart(_ target: HiddenSettingRestart) async throws {
        if failing.contains(target) { throw HiddenSettingsError.restartFailed(target.title) }
        restarted.append(target)
    }
}

final class HiddenSettingCatalogTests: XCTestCase {
    func testIdentifiersAndKeysAreUnique() {
        let ids = HiddenSetting.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let slots = HiddenSetting.catalog.map { $0.domain.rawValue + "/" + $0.key }
        XCTAssertEqual(Set(slots).count, slots.count)
    }

    func testEveryGroupHasSettingsAndDefaultsAreValid() {
        for group in HiddenSettingGroup.allCases {
            XCTAssertFalse(HiddenSetting.catalog.filter { $0.group == group }.isEmpty, group.rawValue)
        }
        for setting in HiddenSetting.catalog {
            XCTAssertTrue(setting.accepts(setting.systemDefault), setting.id)
        }
    }

    /// Keys reach `defaults` and the restart reaches `killall` as plain arguments; keep them inert anyway.
    func testKeysAreSafeTokens() {
        for setting in HiddenSetting.catalog {
            XCTAssertNotNil(setting.key.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression), setting.key)
        }
    }
}

final class HiddenSettingValueTests: XCTestCase {
    private let delay = HiddenSetting.setting(id: "dock.autohide-delay")!
    private let format = HiddenSetting.setting(id: "screencapture.type")!
    private let hiddenFiles = HiddenSetting.setting(id: "finder.AppleShowAllFiles")!

    func testValidationFollowsKind() {
        XCTAssertTrue(delay.accepts(.number(0)))
        XCTAssertTrue(delay.accepts(.number(2)))
        XCTAssertFalse(delay.accepts(.number(2.5)))
        XCTAssertFalse(delay.accepts(.number(.nan)))
        XCTAssertFalse(delay.accepts(.bool(true)))
        XCTAssertTrue(format.accepts(.text("jpg")))
        XCTAssertFalse(format.accepts(.text("jpg; rm -rf ~")))
        XCTAssertFalse(hiddenFiles.accepts(.text("YES")))
    }

    func testDecodesWhatDefaultsMayHaveStored() {
        XCTAssertEqual(hiddenFiles.decode(NSNumber(value: true)), .bool(true))
        XCTAssertEqual(hiddenFiles.decode("YES"), .bool(true), "defaults write … -string YES")
        XCTAssertEqual(hiddenFiles.decode(NSNumber(value: 0)), .bool(false), "defaults write … -int 0")
        XCTAssertNil(hiddenFiles.decode("maybe"))
        XCTAssertEqual(delay.decode(NSNumber(value: 0.15)), .number(0.15))
        XCTAssertEqual(delay.decode("0.3"), .number(0.3))
        XCTAssertEqual(format.decode("JPG"), .text("jpg"))
        XCTAssertNil(format.decode("bmp"))
        XCTAssertNil(delay.decode(nil))
    }

    func testTerminalCommandsMatchDefaultsSyntax() {
        XCTAssertEqual(delay.writeCommand(.number(0)), "defaults write com.apple.dock autohide-delay -float 0")
        XCTAssertEqual(delay.writeCommand(.number(0.15)), "defaults write com.apple.dock autohide-delay -float 0.15")
        XCTAssertEqual(hiddenFiles.writeCommand(.bool(true)), "defaults write com.apple.finder AppleShowAllFiles -bool true")
        XCTAssertEqual(format.writeCommand(.text("heic")), "defaults write com.apple.screencapture type -string heic")
        XCTAssertEqual(delay.deleteCommand, "defaults delete com.apple.dock autohide-delay")
        XCTAssertEqual(delay.restartCommand, "killall Dock")
        let global = HiddenSetting.setting(id: "global.ApplePressAndHoldEnabled")!
        XCTAssertEqual(global.writeCommand(.bool(false)), "defaults write -g ApplePressAndHoldEnabled -bool false")
        XCTAssertNil(global.restartCommand)
    }

    func testNumbersUsePosixFormattingWhateverTheLanguage() {
        XCTAssertEqual(HiddenSetting.formatNumber(0.5), "0.5")
        XCTAssertEqual(HiddenSetting.formatNumber(1), "1")
        XCTAssertEqual(HiddenSetting.formatNumber(0.0499999), "0.05")
    }
}

final class HiddenSettingsServiceTests: XCTestCase {
    private func service(_ store: MemoryStore, _ restarter: RecordingRestarter) -> HiddenSettingsService {
        HiddenSettingsService(store: store, restarter: restarter)
    }

    func testUnsetKeyReportsTheMacOSDefault() {
        let state = service(MemoryStore(), RecordingRestarter()).state(of: HiddenSetting.setting(id: "screencapture.include-date")!)
        XCTAssertEqual(state.value, .bool(true))
        XCTAssertFalse(state.isCustomized)
        XCTAssertFalse(state.isUnrecognized)
    }

    func testStoredValueIsCustomizedAndUnreadableValueFallsBack() {
        let store = MemoryStore()
        store.values["com.apple.dock/autohide-delay"] = NSNumber(value: 0)
        store.values["com.apple.screencapture/type"] = "bmp"
        let sut = service(store, RecordingRestarter())
        XCTAssertEqual(sut.state(of: HiddenSetting.setting(id: "dock.autohide-delay")!),
                       HiddenSettingState(value: .number(0), isCustomized: true, isUnrecognized: false))
        XCTAssertEqual(sut.state(of: HiddenSetting.setting(id: "screencapture.type")!),
                       HiddenSettingState(value: .text("png"), isCustomized: true, isUnrecognized: true))
    }

    func testApplyWritesResetsAndRestartsEachProcessOnceInFixedOrder() async throws {
        let store = MemoryStore()
        store.values["com.apple.finder/QuitMenuItem"] = NSNumber(value: true)
        let restarter = RecordingRestarter()
        let report = try await service(store, restarter).apply([
            .set(id: "finder.AppleShowAllFiles", value: .bool(true)),
            .set(id: "dock.autohide-delay", value: .number(0)),
            .set(id: "dock.showhidden", value: .bool(true)),
            .reset(id: "finder.QuitMenuItem"),
            .set(id: "global.ApplePressAndHoldEnabled", value: .bool(false)),
        ])
        XCTAssertEqual(report.written.count, 5)
        XCTAssertEqual(report.failed, [])
        XCTAssertEqual(report.restarted, [.dock, .finder], "Dock once, Finder once; global settings restart nothing")
        let restarted = await restarter.restarted
        XCTAssertEqual(restarted, [.dock, .finder])
        XCTAssertEqual(store.values["com.apple.finder/AppleShowAllFiles"] as? NSNumber, true)
        XCTAssertNil(store.values["com.apple.finder/QuitMenuItem"], "reset deletes the key")
        XCTAssertEqual(store.values["NSGlobalDomain/ApplePressAndHoldEnabled"] as? NSNumber, false)
    }

    func testInvalidChangeAbortsBeforeAnythingIsWritten() async {
        let store = MemoryStore()
        let restarter = RecordingRestarter()
        do {
            _ = try await service(store, restarter).apply([
                .set(id: "dock.showhidden", value: .bool(true)),
                .set(id: "dock.autohide-delay", value: .number(99)),
            ])
            XCTFail("expected invalidValue")
        } catch {
            XCTAssertEqual(error as? HiddenSettingsError, .invalidValue("dock.autohide-delay"))
        }
        XCTAssertTrue(store.values.isEmpty)
        let restarted = await restarter.restarted
        XCTAssertEqual(restarted, [])
    }

    func testUnknownSettingIsRejected() async {
        do {
            _ = try await service(MemoryStore(), RecordingRestarter()).apply([.set(id: "com.apple.loginwindow.evil", value: .bool(true))])
            XCTFail("expected unknownSetting")
        } catch {
            XCTAssertEqual(error as? HiddenSettingsError, .unknownSetting("com.apple.loginwindow.evil"))
        }
    }

    func testFailedWritesAreReportedAndDoNotTriggerRestarts() async throws {
        let store = MemoryStore()
        store.failingKeys = ["autohide-delay"]
        let restarter = RecordingRestarter()
        let report = try await service(store, restarter).apply([.set(id: "dock.autohide-delay", value: .number(0))])
        XCTAssertEqual(report.failed, ["dock.autohide-delay"])
        XCTAssertEqual(report.restarted, [])
    }

    func testRestartFailureIsReportedWithoutLosingWrites() async throws {
        let store = MemoryStore()
        let restarter = RecordingRestarter()
        await restarter.fail(.finder)
        let report = try await service(store, restarter).apply([.set(id: "finder.QuitMenuItem", value: .bool(true))])
        XCTAssertEqual(report.written, ["finder.QuitMenuItem"])
        XCTAssertEqual(report.restartFailures, [.finder])
    }
}
