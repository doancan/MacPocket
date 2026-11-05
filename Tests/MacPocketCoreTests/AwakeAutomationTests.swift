import XCTest
@testable import MacPocketCore

final class AwakeAutomationTests: XCTestCase {
    private func settings() -> AwakeAutomationSettings {
        var settings = AwakeAutomationSettings(); settings.enabled = true; settings.conditions = [.applicationRunning, .externalPower]
        settings.applicationIDs = ["example.editor"]; settings.maximumMinutes = 1; return settings
    }
    private func input(app: Bool = true, power: Bool? = true, locked: Bool? = false, at: Double = 100) -> AwakeAutomationInput {
        .init(runningApplicationIDs: app ? ["example.editor"] : [], externalDisplay: false, externalPower: power, locked: locked, uptime: at)
    }
    func testDefaultsAreOffAndSettingsPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertFalse(AwakeAutomationSettings.load(from: defaults).enabled)
        let settings = settings(); settings.save(to: defaults)
        XCTAssertEqual(AwakeAutomationSettings.load(from: defaults), settings)
    }
    func testAllAndAnyAreExplicitAndUnknownPowerDoesNotMatch() {
        var policy = AwakeAutomationPolicy(), settings = settings()
        XCTAssertEqual(policy.evaluate(settings, input: input(power: nil), manualSession: false).status, .waiting)
        XCTAssertTrue(policy.evaluate(settings, input: input(), manualSession: false).shouldHold)
        settings.match = .any
        XCTAssertTrue(policy.evaluate(settings, input: input(power: false), manualSession: false).shouldHold)
        XCTAssertEqual(policy.evaluate(settings, input: input(app: false, power: nil), manualSession: false).status, .waiting)
    }
    func testEmptyConditionsAndSelectedAppListCannotActivateImplicitly() {
        var policy = AwakeAutomationPolicy(), settings = settings()
        settings.applicationIDs = []; settings.match = .any
        XCTAssertEqual(policy.evaluate(settings, input: input(), manualSession: false).status, .configure)
        settings.conditions = []
        XCTAssertFalse(policy.evaluate(settings, input: input(), manualSession: false).shouldHold)
    }
    func testManualOverrideWaitsForAnUnsatisfiedThenSatisfiedCycle() {
        var policy = AwakeAutomationPolicy(); let settings = settings()
        policy.pauseForManualControl()
        XCTAssertEqual(policy.evaluate(settings, input: input(), manualSession: false).status, .manualPause)
        XCTAssertEqual(policy.evaluate(settings, input: input(power: false), manualSession: false).status, .waiting)
        XCTAssertTrue(policy.evaluate(settings, input: input(), manualSession: false).shouldHold)
    }
    func testManualSessionExpiryDoesNotImmediatelyStartAutomation() {
        var policy = AwakeAutomationPolicy(); let settings = settings()
        XCTAssertEqual(policy.evaluate(settings, input: input(), manualSession: true).status, .manualSession)
        XCTAssertEqual(policy.evaluate(settings, input: input(at: 200), manualSession: false).status, .manualPause)
        policy.reset()
        XCTAssertTrue(policy.evaluate(settings, input: input(at: 201), manualSession: false).shouldHold)
    }
    func testLockAndUnknownSessionPauseWithoutRenewingTheBudget() {
        var policy = AwakeAutomationPolicy(); let settings = settings()
        XCTAssertTrue(policy.evaluate(settings, input: input(), manualSession: false).shouldHold)
        XCTAssertEqual(policy.evaluate(settings, input: input(locked: true, at: 120), manualSession: false).status, .locked)
        XCTAssertEqual(policy.evaluate(settings, input: input(locked: nil, at: 130), manualSession: false).status, .locked)
        XCTAssertEqual(policy.evaluate(settings, input: input(at: 150), manualSession: false).remainingSeconds, 10)
        XCTAssertEqual(policy.evaluate(settings, input: input(at: 170), manualSession: false).status, .limitReached)
    }
    func testLimitCannotRearmItselfWhileTheConditionStaysTrue() {
        var policy = AwakeAutomationPolicy(); let settings = settings()
        _ = policy.evaluate(settings, input: input(), manualSession: false)
        for at in [160.0, 161, 10_000] { XCTAssertEqual(policy.evaluate(settings, input: input(at: at), manualSession: false).status, .limitReached) }
        _ = policy.evaluate(settings, input: input(app: false, at: 10_001), manualSession: false)
        XCTAssertEqual(policy.evaluate(settings, input: input(at: 10_002), manualSession: false).remainingSeconds, 60)
    }
    func testClockReversalAndInvalidClockNeverExtendAnActiveSession() {
        var policy = AwakeAutomationPolicy(); let settings = settings()
        _ = policy.evaluate(settings, input: input(), manualSession: false)
        for at in [Double.nan, .infinity, -1, 90] { XCTAssertEqual(policy.evaluate(settings, input: input(at: at), manualSession: false).status, .clockUnavailable) }
        XCTAssertEqual(policy.evaluate(settings, input: input(at: 150), manualSession: false).remainingSeconds, 10)
    }
    func testDisablingAndExplicitResetAllowAnIntentionalNewCycle() {
        var policy = AwakeAutomationPolicy(), settings = settings()
        _ = policy.evaluate(settings, input: input(), manualSession: false); policy.pauseForManualControl()
        settings.enabled = false
        XCTAssertEqual(policy.evaluate(settings, input: input(), manualSession: false).status, .disabled)
        settings.enabled = true
        XCTAssertTrue(policy.evaluate(settings, input: input(), manualSession: false).shouldHold)
        policy.reset(); XCTAssertEqual(policy.evaluate(settings, input: input(at: 1000), manualSession: false).remainingSeconds, 60)
    }
    func testExternalDisplaysAndDurationBounds() {
        var policy = AwakeAutomationPolicy(), settings = settings()
        settings.conditions = [.externalDisplay]; settings.maximumMinutes = .max
        let context = AwakeAutomationInput(runningApplicationIDs: [], externalDisplay: true, externalPower: nil, locked: false, uptime: 100)
        XCTAssertEqual(policy.evaluate(settings, input: context, manualSession: false).remainingSeconds, 7200)
        settings.maximumMinutes = 0; XCTAssertEqual(settings.durationSeconds, 7200)
    }
}
