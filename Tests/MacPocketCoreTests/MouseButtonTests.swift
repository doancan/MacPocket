import XCTest
@testable import MacPocketCore

final class MouseButtonTests: XCTestCase {
    private func input(_ id: Int = 3) -> MouseButtonInput { MouseButtonInput(rawValue: id)! }
    func testPrimaryButtonsAndOutOfRangeCannotBeAssigned() {
        for invalid in [-1, 0, 1, 32, 99, 102, Int.max] { XCTAssertNil(MouseButtonInput(rawValue: invalid)) }
        XCTAssertEqual(MouseButtonInput.allCases.count, 32)
        XCTAssertFalse(input(2).isWheel); XCTAssertTrue(input(100).isWheel)
    }
    func testModuleStartsDisabledWithOnlyBackAndForwardDefaults() {
        let settings = MouseButtonSettings()
        XCTAssertFalse(settings.enabled); XCTAssertEqual(settings.bindings.count, 2)
        XCTAssertEqual(settings.bindings["3"]?.keyCombo, KeyCombo(keyCode: 33, modifiers: .command))
        XCTAssertEqual(settings.binding(for: input(), application: "app").action, .native)
    }
    func testPerAppInheritanceExplicitOptOutAndExclusionPriority() {
        var settings = MouseButtonSettings(); settings.enabled = true
        XCTAssertEqual(settings.binding(for: input(), application: "app").action, .back)
        settings.set(.init(.native), for: input(), application: "app")
        XCTAssertEqual(settings.binding(for: input(), application: "app").action, .native)
        XCTAssertEqual(settings.binding(for: input(), application: "other").action, .back)
        settings.set(.init(.copy), for: input(), application: "app")
        XCTAssertEqual(settings.binding(for: input(), application: "app").action, .copy)
        settings.excludedBundleIDs = ["app"]
        XCTAssertEqual(settings.binding(for: input(), application: "app").action, .native)
        settings.excludedBundleIDs = []; settings.set(nil, for: input(), application: "app")
        XCTAssertEqual(settings.binding(for: input(), application: "app").action, .back)
    }
    func testIncompleteAndUnsupportedShortcutsPassThrough() {
        XCTAssertFalse(MouseButtonBinding(.shortcut).isExecutable)
        XCTAssertFalse(MouseButtonBinding(.shortcut, shortcut: .init(keyCode: .max, modifiers: .command)).isExecutable)
        XCTAssertFalse(MouseButtonBinding(.shortcut, shortcut: .init(keyCode: 8, modifiers: .init(rawValue: 32))).isExecutable)
        XCTAssertTrue(MouseButtonBinding(.shortcut, shortcut: .init(keyCode: 36, modifiers: [])).isExecutable)
        XCTAssertTrue(MouseButtonBinding(.shelf).isExecutable)
    }
    func testConsumedPressOwnsDragAndReleaseAcrossSettingsChange() {
        var router = MouseButtonRouter()
        XCTAssertEqual(router.button(3, phase: .down, proposed: .init(.copy)), .perform(.init(.copy)))
        XCTAssertEqual(router.button(3, phase: .drag, proposed: nil), .consume)
        XCTAssertEqual(router.button(3, phase: .up, proposed: nil), .consume)
        XCTAssertEqual(router.button(3, phase: .up, proposed: .init(.paste)), .pass)
        XCTAssertTrue(router.pressed.isEmpty)
    }
    func testUnmappedPressNeverSwallowsItsReleaseWhenMappingIsAdded() {
        var router = MouseButtonRouter()
        XCTAssertEqual(router.button(3, phase: .down, proposed: nil), .pass)
        XCTAssertEqual(router.button(3, phase: .drag, proposed: .init(.copy)), .pass)
        XCTAssertEqual(router.button(3, phase: .up, proposed: .init(.copy)), .pass)
    }
    func testDuplicateDownDoesNotFireTwiceAndMultipleButtonsAreIndependent() {
        var router = MouseButtonRouter()
        XCTAssertEqual(router.button(3, phase: .down, proposed: .init(.copy)), .perform(.init(.copy)))
        XCTAssertEqual(router.button(3, phase: .down, proposed: .init(.paste)), .consume)
        XCTAssertEqual(router.button(4, phase: .down, proposed: .init(.paste)), .perform(.init(.paste)))
        XCTAssertEqual(router.pressed, [3, 4])
        XCTAssertEqual(router.button(3, phase: .up, proposed: nil), .consume); XCTAssertEqual(router.pressed, [4])
        router.reset(); XCTAssertTrue(router.pressed.isEmpty)
    }
    func testPrimaryButtonRemainsNativeEvenWithProposedAction() {
        var router = MouseButtonRouter()
        for id in [0, 1, 100] { XCTAssertEqual(router.button(id, phase: .down, proposed: .init(.copy)), .pass) }
    }
    func testSideWheelIgnoresContinuousDiagonalVerticalAndInvalidPackets() {
        XCTAssertEqual(MouseButtonInput.wheel(vertical: 0, horizontal: 2, continuous: false), input(100))
        XCTAssertEqual(MouseButtonInput.wheel(vertical: 0, horizontal: -2, continuous: false), input(101))
        XCTAssertNil(MouseButtonInput.wheel(vertical: 0, horizontal: 2, continuous: true))
        XCTAssertNil(MouseButtonInput.wheel(vertical: 2, horizontal: 2, continuous: false))
        XCTAssertNil(MouseButtonInput.wheel(vertical: -3, horizontal: 2, continuous: false))
        XCTAssertNil(MouseButtonInput.wheel(vertical: .nan, horizontal: 2, continuous: false))
        XCTAssertNil(MouseButtonInput.wheel(vertical: 0, horizontal: .infinity, continuous: false))
    }
    func testSideWheelBurstGateConsumesChatterAndRearmsAfterQuietOrDirectionChange() {
        var router = MouseButtonRouter(); let action = MouseButtonBinding(.copy)
        XCTAssertEqual(router.wheel(input(100), at: 1, proposed: action), .perform(action))
        XCTAssertEqual(router.wheel(input(100), at: 1.01, proposed: action), .consume)
        XCTAssertEqual(router.wheel(input(100), at: 1.1, proposed: action), .consume)
        XCTAssertEqual(router.wheel(input(101), at: 1.11, proposed: action), .perform(action))
        XCTAssertEqual(router.wheel(input(101), at: 1.4, proposed: action), .perform(action))
        XCTAssertEqual(router.wheel(input(100), at: .nan, proposed: action), .pass)
        router.reset(); XCTAssertEqual(router.wheel(input(101), at: 1.41, proposed: action), .perform(action))
    }
    func testRoundTripAndFilteringOfImportedInvalidButtons() throws {
        let name = "MouseButtonTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        var settings = MouseButtonSettings(); settings.enabled = true
        settings.set(.init(.shortcut, shortcut: .init(keyCode: 8, modifiers: [.command, .shift])), for: input(8), application: "app")
        settings.excludedBundleIDs = ["other"]; settings.save(to: defaults)
        XCTAssertEqual(MouseButtonSettings.load(from: defaults), settings)
        settings.bindings["0"] = .init(.copy); settings.bindings["garbage"] = .init(.paste)
        settings.profiles["app"]?["1"] = .init(.copy); settings.save(to: defaults)
        let loaded = MouseButtonSettings.load(from: defaults)
        XCTAssertNil(loaded.bindings["0"]); XCTAssertNil(loaded.bindings["garbage"]); XCTAssertNil(loaded.profiles["app"]?["1"])
        defaults.set(Data("bad".utf8), forKey: MouseButtonSettings.storageKey)
        XCTAssertFalse(MouseButtonSettings.load(from: defaults).enabled)
    }
    func testExtremeScrollDeltaAndMutatedSettingsAreFiniteAndBounded() {
        var settings = MouseScrollSettings(); settings.enabled = true; settings.linear = false; settings.speed = .infinity
        XCTAssertEqual(MouseScrollTransform.plan(vertical: .min, horizontal: .max, isContinuous: false, settings: settings), .lines(vertical: -10_000, horizontal: 10_000))
        settings.smooth = true
        XCTAssertEqual(MouseScrollTransform.plan(vertical: .min, horizontal: .max, isContinuous: false, settings: settings), .glide(vertical: -100_000, horizontal: 100_000))
    }
    func testSmoothScrollRejectsNonfiniteInputAndBoundsBacklog() {
        var scroller = SmoothScroller(); scroller.add(vertical: .nan, horizontal: 1, frames: 10)
        XCTAssertTrue(scroller.isIdle)
        scroller.add(vertical: .greatestFiniteMagnitude, horizontal: -.greatestFiniteMagnitude, frames: .max)
        var count = 0, total = 0.0
        while !scroller.isIdle { let step = scroller.nextFrame(); XCTAssertTrue(step.vertical.isFinite); total += step.vertical; count += 1 }
        XCTAssertEqual(count, 240); XCTAssertEqual(total, 1_000_000, accuracy: 0.001)
    }
}
