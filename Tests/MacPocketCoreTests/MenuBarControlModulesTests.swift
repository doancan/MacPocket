import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

/// Keep awake, focus and Bluetooth battery modules: readings built outside the system snapshot.
final class MenuBarControlModulesTests: XCTestCase {
    func testClipboardShowsTheCountTheAppProvides() {
        let count = MenuBarReading(lines: ["12"], reserve: ["999"], fraction: nil, magnitude: 12, accessibility: "12 öğe")
        let reading = MenuBarFormatter.reading(.clipboard, settings: .defaults(for: .clipboard), snapshot: nil, external: count)
        XCTAssertEqual(reading, count)
    }

    func testClipboardLivesInTheGroupedPopoverNotBesideIt() {
        XCTAssertFalse(MenuBarModule.clipboard.keepsOwnItemWhenGrouped)
        XCTAssertTrue(MenuBarModule.clock.keepsOwnItemWhenGrouped)
        XCTAssertFalse(MenuBarModule.cpu.keepsOwnItemWhenGrouped)
    }

    func testDefaultTabsAreTheEverydayOnes() {
        let enabled = MenuBarModule.allCases.filter(\.enabledByDefault)
        XCTAssertEqual(Set(enabled), [.overview, .cpu, .memory, .network, .clipboard])
    }

    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    func testNewModulesAreNotSystemMetricsAndStartDisabled() {
        for module in [MenuBarModule.awake, .bluetooth, .display, .weather, .aiUsage] {
            XCTAssertFalse(module.isSystemMetric, "\(module)")
            XCTAssertFalse(module.enabledByDefault, "\(module)")
        }
        for module in [MenuBarModule.awake, .bluetooth, .display] { XCTAssertEqual(module.valueOptions.count, 1, "\(module)") }
        XCTAssertTrue([MenuBarModule.cpu, .gpu, .memory, .disk, .network, .power].allSatisfy(\.isSystemMetric))
        XCTAssertEqual(MenuBarModuleSettings.defaults(for: .bluetooth).colorMode, .thresholds)
        XCTAssertTrue(MenuBarValue.bluetoothLowest.lowerIsWorse)
        XCTAssertNil(MenuBarValue.awakeRemaining.thresholdUnit)
    }

    func testStoredOrderGainsTheNewModulesAtTheEnd() {
        let defaults = temporaryDefaults()
        defaults.set(MenuBarPreferences.schemaVersion, forKey: MenuBarPreferences.schemaKey)
        defaults.set("network,cpu,gpu,memory,disk,power,weather,aiUsage", forKey: MenuBarPreferences.orderKey)
        let loaded = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(loaded.order.first, .overview, "the overview leads orders saved before it existed")
        XCTAssertEqual(loaded.order.suffix(8), [.awake, .bluetooth, .display, .clock, .clipboard, .health, .timeline, .launcher])
        XCTAssertFalse(loaded.enabled.contains(.awake))
    }

    func testAwakeReadingCoversOffTimedAndIndefinite() {
        let off = MenuBarFormatter.awakeReading(nil, now: now)
        XCTAssertEqual(off.lines, [""])
        XCTAssertEqual(off.symbol, "cup.and.saucer")
        XCTAssertNil(off.fraction)
        let inactive = AwakeSession(startedAt: now, endsAt: now + 600, keepDisplayAwake: true, active: false)
        XCTAssertEqual(MenuBarFormatter.awakeReading(inactive, now: now).symbol, "cup.and.saucer")

        let timed = AwakeSession(startedAt: now - 600, endsAt: now + 2_790, keepDisplayAwake: true)
        let reading = MenuBarFormatter.awakeReading(timed, now: now)
        XCTAssertEqual(reading.lines, [MenuBarFormatter.duration(minutes: 47)], "46.5 minutes round up to 47")
        XCTAssertEqual(reading.symbol, "cup.and.saucer.fill")
        XCTAssertEqual(reading.fraction ?? -1, 2_790 / 3_390, accuracy: 0.0001)

        let long = AwakeSession(startedAt: now, endsAt: now + 7_200, keepDisplayAwake: false)
        XCTAssertEqual(MenuBarFormatter.awakeReading(long, now: now).lines, ["2:00"])
        XCTAssertEqual(MenuBarFormatter.awakeReading(long, now: now + 7_300).lines, [MenuBarFormatter.duration(minutes: 0)], "never negative")

        let forever = MenuBarFormatter.awakeReading(AwakeSession(startedAt: now, endsAt: nil, keepDisplayAwake: true), now: now)
        XCTAssertEqual(forever.lines, ["∞"])
        XCTAssertEqual(forever.fraction, 1)
    }

    func testBluetoothReadingShowsTheAccessoryThatRunsOutFirst() {
        let keyboard = BluetoothBatteryDevice(address: "A", name: "Magic Keyboard", kind: .keyboard, levels: .init(main: 64))
        let pods = BluetoothBatteryDevice(address: "B", name: "AirPods", kind: .headphones, levels: .init(left: 80, right: 18, batteryCase: 5))
        let unknown = BluetoothBatteryDevice(address: "C", name: "MX Master", kind: .mouse, levels: .init())
        let reading = MenuBarFormatter.bluetoothReading([keyboard, pods, unknown])
        XCTAssertEqual(reading.lines, [MenuBarFormatter.percent(18, decimals: false)])
        XCTAssertEqual(reading.symbol, "airpodspro")
        XCTAssertEqual(reading.thresholdValue, 18)
        XCTAssertTrue(reading.accessibility.contains("AirPods"))

        var settings = MenuBarModuleSettings.defaults(for: .bluetooth)
        XCTAssertEqual(MenuBarThresholds.level(reading, settings: settings), .warning, "18% is under the 20% warning, above the 10% critical")
        settings.criticalThreshold = 20
        XCTAssertEqual(MenuBarThresholds.level(reading, settings: settings), .critical)

        let empty = MenuBarFormatter.bluetoothReading([])
        XCTAssertEqual(empty.lines, ["—"])
        XCTAssertNil(empty.thresholdValue)
        XCTAssertEqual(MenuBarFormatter.bluetoothReading([unknown]).lines, ["—"])
    }

    func testDisplayReadingFollowsBrightnessAndNightMode() {
        let day = MenuBarFormatter.displayReading(level: 0.72, displays: 2, night: .off)
        XCTAssertEqual(day.lines, [MenuBarFormatter.percent(72, decimals: false)])
        XCTAssertEqual(day.fraction ?? -1, 0.72, accuracy: 0.0001)
        XCTAssertEqual(day.symbol, "sun.max.fill")
        XCTAssertNil(day.thresholdValue, "brightness has no alarm level")
        XCTAssertEqual(MenuBarFormatter.displayReading(level: 0.3, displays: 1, night: .off).symbol, "sun.min.fill")
        XCTAssertEqual(MenuBarFormatter.displayReading(level: 0.3, displays: 1, night: .active(night: 0)).symbol, "sun.min.fill",
                       "night mode on but still daytime: no moon")
        XCTAssertEqual(MenuBarFormatter.displayReading(level: 0.3, displays: 1, night: .active(night: 0.4)).symbol, "moon.fill")
        XCTAssertEqual(MenuBarFormatter.displayReading(level: 0.8, displays: 1, night: .paused).symbol, "moon.zzz")
        XCTAssertEqual(MenuBarFormatter.displayReading(level: 1.4, displays: 1, night: .off).fraction, 1, "clamped")
        let none = MenuBarFormatter.displayReading(level: nil, displays: 0, night: .active(night: 1))
        XCTAssertEqual(none.lines, ["—"])
        XCTAssertEqual(none.symbol, "moon.fill")
        XCTAssertNil(none.fraction)
        XCTAssertEqual(MenuBarFormatter.reading(.display, settings: .defaults(for: .display), snapshot: nil, external: day), day)
    }

    func testGenericReadingPassesExternalReadingsThrough() {
        let settings = MenuBarModuleSettings.defaults(for: .awake)
        let external = MenuBarFormatter.awakeReading(AwakeSession(startedAt: now, endsAt: now + 60, keepDisplayAwake: false), now: now)
        XCTAssertEqual(MenuBarFormatter.reading(.awake, settings: settings, snapshot: nil, external: external), external)
        XCTAssertEqual(MenuBarFormatter.reading(.awake, settings: .defaults(for: .awake), snapshot: nil).lines, [""])
    }
}
