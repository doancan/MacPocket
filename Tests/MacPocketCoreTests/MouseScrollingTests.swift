import XCTest
@testable import MacPocketCore

final class MouseScrollTransformTests: XCTestCase {
    private var settings: MouseScrollSettings {
        var settings = MouseScrollSettings()
        settings.enabled = true
        return settings
    }

    func testTrackpadAndDisabledPassThrough() {
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 5, horizontal: 0, isContinuous: true, settings: settings), .pass)
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 5, horizontal: 0, isContinuous: false, settings: MouseScrollSettings()), .pass)
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 0, horizontal: 0, isContinuous: false, settings: settings), .pass)
    }

    func testLinearMakesEveryNotchTheSameDistance() {
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 1, horizontal: 0, isContinuous: false, settings: settings), .lines(vertical: 3, horizontal: 0))
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 9, horizontal: 0, isContinuous: false, settings: settings), .lines(vertical: 3, horizontal: 0),
                       "a fast spin no longer accelerates")
        var accelerated = settings
        accelerated.linear = false
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 9, horizontal: 0, isContinuous: false, settings: accelerated), .lines(vertical: 9, horizontal: 0))
    }

    func testReversesEachAxisIndependently() {
        var reversed = settings
        reversed.reverseVertical = true
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 2, horizontal: -1, isContinuous: false, settings: reversed),
                       .lines(vertical: -3, horizontal: -3))
        reversed.reverseHorizontal = true
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 2, horizontal: -1, isContinuous: false, settings: reversed),
                       .lines(vertical: -3, horizontal: 3))
    }

    func testSpeedAndAtLeastOneLine() {
        var slow = settings
        slow.linesPerNotch = 1
        slow.speed = 0.5
        XCTAssertEqual(MouseScrollTransform.plan(vertical: -1, horizontal: 0, isContinuous: false, settings: slow), .lines(vertical: -1, horizontal: 0))
    }

    func testSmoothGlidesInPoints() {
        var smooth = settings
        smooth.smooth = true
        smooth.speed = 2
        XCTAssertEqual(MouseScrollTransform.plan(vertical: 1, horizontal: 0, isContinuous: false, settings: smooth), .glide(vertical: 60, horizontal: 0))
    }
}

final class SmoothScrollerTests: XCTestCase {
    func testDeliversExactlyTheDistanceWithEaseOut() {
        var scroller = SmoothScroller()
        scroller.add(vertical: 90, horizontal: -30, frames: 6)
        var steps: [Double] = []
        var horizontal = 0.0
        while !scroller.isIdle { let step = scroller.nextFrame(); steps.append(step.vertical); horizontal += step.horizontal }
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps.reduce(0, +), 90, accuracy: 0.0001)
        XCTAssertEqual(horizontal, -30, accuracy: 0.0001)
        XCTAssertGreaterThan(steps[0], steps[4], "starts fast, slows down")
    }

    func testNewNotchesAddToWhatIsLeft() {
        var scroller = SmoothScroller()
        scroller.add(vertical: 30, horizontal: 0, frames: 5)
        let first = scroller.nextFrame().vertical
        scroller.add(vertical: 30, horizontal: 0, frames: 5)
        var total = first
        while !scroller.isIdle { total += scroller.nextFrame().vertical }
        XCTAssertEqual(total, 60, accuracy: 0.0001)
        XCTAssertEqual(scroller.nextFrame().vertical, 0)
    }

    func testSettingsClampOnLoad() {
        let defaults = UserDefaults(suiteName: "MouseScrollTests")!
        defer { defaults.removePersistentDomain(forName: "MouseScrollTests") }
        var settings = MouseScrollSettings()
        settings.linesPerNotch = 50
        settings.speed = 9
        settings.save(to: defaults)
        let loaded = MouseScrollSettings.load(from: defaults)
        XCTAssertEqual(loaded.linesPerNotch, 10)
        XCTAssertEqual(loaded.speed, 3)
    }
}
