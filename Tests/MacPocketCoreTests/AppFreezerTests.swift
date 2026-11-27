import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class AppFreezerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings: AppFreezerSettings {
        var settings = AppFreezerSettings()
        settings.enabled = true
        settings.rules = [AppFreezeRule(bundleID: "com.google.Chrome", delayMinutes: 5)]
        return settings
    }

    private func app(_ id: String = "com.google.Chrome", front: Bool = false, idle minutes: Double, frozen: Bool = false) -> AppFreezer.AppState {
        AppFreezer.AppState(bundleID: id, isFrontmost: front, backgroundSince: now - minutes * 60, isFrozen: frozen)
    }

    func testFreezesOnlyAfterTheDelayInTheBackground() {
        XCTAssertNil(AppFreezer.decide(app(idle: 4.9), settings: settings, now: now))
        XCTAssertEqual(AppFreezer.decide(app(idle: 5), settings: settings, now: now), .freeze)
        XCTAssertNil(AppFreezer.decide(app(front: true, idle: 60), settings: settings, now: now), "never the app in front")
        XCTAssertNil(AppFreezer.decide(app("com.apple.Safari", idle: 60), settings: settings, now: now), "no rule, no freeze")
    }

    func testThawsWhenBroughtForwardRuleRemovedOrFeatureOff() {
        XCTAssertEqual(AppFreezer.decide(app(front: true, idle: 0, frozen: true), settings: settings, now: now), .thaw)
        XCTAssertNil(AppFreezer.decide(app(idle: 10, frozen: true), settings: settings, now: now), "stays frozen")
        var off = settings
        off.enabled = false
        XCTAssertEqual(AppFreezer.decide(app(idle: 10, frozen: true), settings: off, now: now), .thaw)
        var noRule = settings
        noRule.rules = []
        XCTAssertEqual(AppFreezer.decide(app(idle: 10, frozen: true), settings: noRule, now: now), .thaw)
    }

    func testSystemAppsAndMacPocketAreNeverFrozenEvenWithARule() {
        var risky = settings
        risky.rules = [AppFreezeRule(bundleID: "com.apple.finder", delayMinutes: 1), AppFreezeRule(bundleID: "com.doancan.MacPocket", delayMinutes: 1)]
        XCTAssertNil(AppFreezer.decide(app("com.apple.finder", idle: 99), settings: risky, now: now))
        XCTAssertNil(AppFreezer.decide(app("com.doancan.MacPocket", idle: 99), settings: risky, now: now))
        XCTAssertEqual(AppFreezer.decide(app("com.apple.finder", idle: 99, frozen: true), settings: risky, now: now), .thaw)
    }

    func testLoadingDropsRulesForProtectedApps() {
        let defaults = temporaryDefaults()
        var stored = settings
        stored.rules.append(AppFreezeRule(bundleID: "com.apple.dock", delayMinutes: 1))
        stored.save(to: defaults)
        XCTAssertEqual(AppFreezerSettings.load(from: defaults).rules.map(\.bundleID), ["com.google.Chrome"])
    }

    func testHasWorkNeedsEnabledAndRules() {
        XCTAssertFalse(AppFreezerSettings().hasWork)
        var enabledWithoutRules = AppFreezerSettings()
        enabledWithoutRules.enabled = true
        XCTAssertFalse(enabledWithoutRules.hasWork)
        XCTAssertTrue(settings.hasWork)
        var disabled = settings
        disabled.enabled = false
        XCTAssertFalse(disabled.hasWork)
    }
}
