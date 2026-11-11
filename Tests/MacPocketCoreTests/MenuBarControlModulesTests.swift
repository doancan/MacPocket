import XCTest
@testable import MacPocketCore

/// Keep awake, focus and Bluetooth battery modules: readings built outside the system snapshot.
final class MenuBarControlModulesTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    func testNewModulesAreNotSystemMetricsAndStartDisabled() {
        for module in [MenuBarModule.awake, .focus, .bluetooth, .display, .weather, .aiUsage] {
            XCTAssertFalse(module.isSystemMetric, "\(module)")
            XCTAssertFalse(module.enabledByDefault, "\(module)")
        }
        for module in [MenuBarModule.awake, .focus, .bluetooth, .display] { XCTAssertEqual(module.valueOptions.count, 1, "\(module)") }
        XCTAssertTrue([MenuBarModule.cpu, .gpu, .memory, .disk, .network, .power].allSatisfy(\.isSystemMetric))
        XCTAssertEqual(MenuBarModuleSettings.defaults(for: .bluetooth).colorMode, .thresholds)
        XCTAssertTrue(MenuBarValue.bluetoothLowest.lowerIsWorse)
        XCTAssertNil(MenuBarValue.awakeRemaining.thresholdUnit)
    }

    func testStoredOrderGainsTheNewModulesAtTheEnd() {
        let suite = "MacPocket.MenuBarControl." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(MenuBarPreferences.schemaVersion, forKey: MenuBarPreferences.schemaKey)
        defaults.set("network,cpu,gpu,memory,disk,power,weather,aiUsage", forKey: MenuBarPreferences.orderKey)
        let loaded = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(loaded.order.suffix(5), [.awake, .focus, .bluetooth, .display, .clock])
        XCTAssertFalse(loaded.enabled.contains(.awake))
    }

    func testAwakeReadingCoversOffTimedAndIndefinite() {
        let off = MenuBarFormatter.awakeReading(nil, now: now)
        XCTAssertEqual(off.lines, [""]); XCTAssertEqual(off.symbol, "cup.and.saucer"); XCTAssertNil(off.fraction)
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
        XCTAssertEqual(forever.lines, ["∞"]); XCTAssertEqual(forever.fraction, 1)
    }

    func testFocusReadingFillsAsTheSessionProgresses() {
        let idle = MenuBarFormatter.focusReading(startedAt: nil, endsAt: nil, now: now)
        XCTAssertEqual(idle.lines, [""]); XCTAssertNil(idle.fraction)
        let running = MenuBarFormatter.focusReading(startedAt: now - 1_500, endsAt: now + 1_500, now: now)
        XCTAssertEqual(running.lines, [MenuBarFormatter.duration(minutes: 25)])
        XCTAssertEqual(running.fraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(MenuBarFormatter.focusReading(startedAt: now - 3_000, endsAt: now - 1, now: now).fraction, 1)
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
        XCTAssertEqual(empty.lines, ["—"]); XCTAssertNil(empty.thresholdValue)
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
        XCTAssertEqual(none.lines, ["—"]); XCTAssertEqual(none.symbol, "moon.fill"); XCTAssertNil(none.fraction)
        XCTAssertEqual(MenuBarFormatter.reading(.display, settings: .defaults(for: .display), snapshot: nil, external: day), day)
    }

    func testGenericReadingPassesExternalReadingsThrough() {
        let settings = MenuBarModuleSettings.defaults(for: .focus)
        let external = MenuBarFormatter.focusReading(startedAt: now, endsAt: now + 60, now: now)
        XCTAssertEqual(MenuBarFormatter.reading(.focus, settings: settings, snapshot: nil, external: external), external)
        XCTAssertEqual(MenuBarFormatter.reading(.awake, settings: .defaults(for: .awake), snapshot: nil).lines, [""])
    }
}
