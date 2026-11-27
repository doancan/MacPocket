import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class ModuleLifecycleTests: XCTestCase {
    @MainActor
    func testLazyLaunchAndRepeatedReconciliation() {
        let defaults = temporaryDefaults()
        defaults.set(false, forKey: PocketModule.clipboard.availabilityKey)
        var starts = 0
        var stops = 0
        let runtime = ModuleLifecycle(defaults: defaults, bindings: [
            .clipboard: .init(start: { starts += 1 }, stop: { stops += 1 })
        ])
        runtime.reconcile()
        runtime.reconcile()
        XCTAssertEqual(starts, 0, "Disabled service closures must never run at launch")
        XCTAssertEqual(stops, 0, "Stopping a never-created singleton would instantiate it")
        XCTAssertTrue(runtime.setAvailable(.clipboard, true))
        runtime.reconcile()
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(runtime.setAvailable(.clipboard, false))
        runtime.reconcile()
        XCTAssertEqual(stops, 1)
        XCTAssertTrue(runtime.running.isEmpty)
        XCTAssertTrue(runtime.setAvailable(.clipboard, true))
        XCTAssertEqual(starts, 2)
    }

    @MainActor
    func testRefusedStopAndImportedPreferences() {
        let defaults = temporaryDefaults()
        var busy = true
        var stops = 0
        let runtime = ModuleLifecycle(defaults: defaults, bindings: [
            .recorder: .init(start: {}, stop: { stops += 1 }, canStop: { !busy })
        ])
        runtime.reconcile()
        XCTAssertFalse(runtime.setAvailable(.recorder, false))
        XCTAssertTrue(PocketModule.recorder.isAvailable(in: defaults))
        defaults.set(false, forKey: PocketModule.recorder.availabilityKey)
        XCTAssertEqual(runtime.reconcile(), [.recorder])
        XCTAssertTrue(PocketModule.recorder.isAvailable(in: defaults))
        XCTAssertEqual(stops, 0)
        busy = false
        XCTAssertTrue(runtime.setAvailable(.recorder, false))
        XCTAssertEqual(stops, 1)
        defaults.removeObject(forKey: PocketModule.recorder.availabilityKey)
        runtime.reconcile()
        XCTAssertEqual(runtime.running, [.recorder], "Reset restores the default availability")
    }

    @MainActor
    func testShutdownPreservesSettingsAndDoesNotStartUnusedBindings() {
        let defaults = temporaryDefaults()
        defaults.set(false, forKey: PocketModule.mixer.availabilityKey)
        defaults.set("saved-custom-shortcut", forKey: "tool-settings")
        var events: [String] = []
        let runtime = ModuleLifecycle(defaults: defaults, bindings: [
            .clipboard: .init(start: { events.append("start clipboard") }, stop: { events.append("stop clipboard") }),
            .mixer: .init(start: { XCTFail("Disabled mixer started") }, stop: { XCTFail("Disabled mixer stopped") }),
            .shelf: .init(start: { events.append("start shelf") }, stop: { events.append("stop shelf") })
        ])
        runtime.reconcile()
        runtime.stopAll()
        runtime.stopAll()
        XCTAssertEqual(events, ["start clipboard", "start shelf", "stop shelf", "stop clipboard"])
        XCTAssertEqual(defaults.string(forKey: "tool-settings"), "saved-custom-shortcut")
        XCTAssertTrue(PocketModule.clipboard.isAvailable(in: defaults))
        XCTAssertFalse(PocketModule.mixer.isAvailable(in: defaults))
    }
}
