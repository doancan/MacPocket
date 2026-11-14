import XCTest
@testable import MacPocketCore

final class IdleDisplayOffTests: XCTestCase {
    private func settings(enabled: Bool = true, minutes: Int = 5) -> IdleDisplayOffSettings {
        var value = IdleDisplayOffSettings(); value.enabled = enabled; value.minutes = minutes; return value
    }
    private func session(keepDisplay: Bool = false, active: Bool = true) -> AwakeSession {
        AwakeSession(startedAt: Date(), endsAt: nil, keepDisplayAwake: keepDisplay, active: active)
    }

    func testDefaultsAreOffAndSettingsPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertFalse(IdleDisplayOffSettings.load(from: defaults).enabled)
        let saved = settings(minutes: 10); saved.save(to: defaults)
        XCTAssertEqual(IdleDisplayOffSettings.load(from: defaults), saved)
    }

    func testInvalidMinutesFallBackToDefault() {
        XCTAssertEqual(settings(minutes: 0).thresholdSeconds, 300)
        XCTAssertEqual(settings(minutes: 99_999).thresholdSeconds, 300)
        XCTAssertEqual(settings(minutes: 1).thresholdSeconds, 60)
    }

    func testFiresOnlyAfterThresholdWhileSystemIsHeld() {
        var policy = IdleDisplayOffPolicy()
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 299, session: session()))
        XCTAssertTrue(policy.shouldSleepDisplay(settings(), idleSeconds: 300, session: session()))
    }

    func testFiresOncePerIdlePeriodAndRearmsAfterInput() {
        var policy = IdleDisplayOffPolicy()
        XCTAssertTrue(policy.shouldSleepDisplay(settings(), idleSeconds: 301, session: session()))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 330, session: session()))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 2, session: session()))
        XCTAssertTrue(policy.shouldSleepDisplay(settings(), idleSeconds: 305, session: session()))
    }

    func testNeverFiresWithoutAnActiveSessionOrWhenDisplayIsHeldOrDisabled() {
        var policy = IdleDisplayOffPolicy()
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 9_999, session: nil))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 9_999, session: session(active: false)))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 9_999, session: session(keepDisplay: true)))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(enabled: false), idleSeconds: 9_999, session: session()))
    }

    func testUnreadableOrInvalidIdleTimeNeverFires() {
        var policy = IdleDisplayOffPolicy()
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: nil, session: session()))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: .infinity, session: session()))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: -1, session: session()))
    }

    func testEndingTheSessionRearmsForTheNextOne() {
        var policy = IdleDisplayOffPolicy()
        XCTAssertTrue(policy.shouldSleepDisplay(settings(), idleSeconds: 400, session: session()))
        XCTAssertFalse(policy.shouldSleepDisplay(settings(), idleSeconds: 410, session: nil))
        XCTAssertTrue(policy.shouldSleepDisplay(settings(), idleSeconds: 420, session: session()))
    }
}
