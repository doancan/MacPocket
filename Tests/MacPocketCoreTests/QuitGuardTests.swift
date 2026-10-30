import XCTest
@testable import MacPocketCore

final class QuitGuardTests: XCTestCase {
    private var guardState = QuitGuard()

    private func send(_ event: QuitGuard.Event, quit: QuitGuardMode = .hold, close: QuitGuardMode = .doublePress) -> [QuitGuard.Effect] {
        guardState.handle(event, mode: { $0 == .quit ? quit : close }, holdDuration: 0.6, doublePressInterval: 0.5)
    }

    func testHoldFiresOnlyAfterTheFullDuration() {
        XCTAssertEqual(send(.keyDown(.quit, isRepeat: false, at: 0)), [.swallow, .hint(.quit, mode: .hold, progress: 0)])
        XCTAssertEqual(send(.keyDown(.quit, isRepeat: true, at: 0.1)), [.swallow], "auto-repeat while held")
        XCTAssertEqual(send(.tick(at: 0.3)), [.hint(.quit, mode: .hold, progress: 0.5)])
        XCTAssertEqual(send(.tick(at: 0.61)), [.hideHint, .fire(.quit)])
        XCTAssertFalse(guardState.isHolding)
        XCTAssertEqual(send(.tick(at: 0.8)), [], "fires once")
    }

    func testReleasingEarlyCancels() {
        _ = send(.keyDown(.quit, isRepeat: false, at: 0))
        XCTAssertEqual(send(.released(at: 0.2)), [.hideHint])
        XCTAssertEqual(send(.tick(at: 1)), [])
    }

    func testDoublePressPassesTheSecondPressWithinTheInterval() {
        XCTAssertEqual(send(.keyDown(.closeWindow, isRepeat: false, at: 0)), [.swallow, .hint(.closeWindow, mode: .doublePress, progress: nil)])
        XCTAssertEqual(send(.keyDown(.closeWindow, isRepeat: false, at: 0.4)), [.hideHint, .pass])
    }

    func testDoublePressTooSlowStartsOverAndHintExpires() {
        _ = send(.keyDown(.closeWindow, isRepeat: false, at: 0))
        XCTAssertEqual(send(.tick(at: 0.6)), [.hideHint])
        XCTAssertEqual(send(.keyDown(.closeWindow, isRepeat: false, at: 0.7)), [.swallow, .hint(.closeWindow, mode: .doublePress, progress: nil)])
    }

    func testDoublePressNeedsTheSameShortcut() {
        _ = send(.keyDown(.closeWindow, isRepeat: false, at: 0), quit: .doublePress)
        XCTAssertEqual(send(.keyDown(.quit, isRepeat: false, at: 0.2), quit: .doublePress),
                       [.swallow, .hint(.quit, mode: .doublePress, progress: nil)])
    }

    func testOffPassesThrough() {
        XCTAssertEqual(send(.keyDown(.closeWindow, isRepeat: false, at: 0), close: .off), [.pass])
    }

    func testOffByDefault() {
        XCTAssertFalse(QuitGuardSettings().isActive)
    }

    func testScope() {
        var settings = QuitGuardSettings()
        XCTAssertTrue(settings.protects("com.apple.Safari"))
        XCTAssertFalse(settings.protects("com.apple.finder"))
        settings.scope = .only
        settings.apps = ["com.apple.Safari"]
        XCTAssertTrue(settings.protects("com.apple.Safari"))
        XCTAssertFalse(settings.protects("com.apple.Terminal"))
        XCTAssertFalse(settings.protects(nil))
    }

    func testSettingsRoundTripClampsDurations() throws {
        let defaults = UserDefaults(suiteName: "QuitGuardTests")!
        defer { defaults.removePersistentDomain(forName: "QuitGuardTests") }
        var settings = QuitGuardSettings()
        settings.holdDuration = 9
        settings.closeMode = .hold
        settings.save(to: defaults)
        let loaded = QuitGuardSettings.load(from: defaults)
        XCTAssertEqual(loaded.holdDuration, 2)
        XCTAssertEqual(loaded.closeMode, .hold)
        XCTAssertTrue(loaded.isActive)
    }
}
