import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class NetworkCounterTests: XCTestCase {
    func testPlainIncreaseIsDifference() {
        XCTAssertEqual(CounterDelta.bytes(previous: 1_000, current: 4_500, bitWidth: 32), 3_500)
    }

    func testThirtyTwoBitWrapIsCounted() {
        let previous = UInt64(UInt32.max) - 99
        XCTAssertEqual(CounterDelta.bytes(previous: previous, current: 100, bitWidth: 32), 200)
    }

    func testDecreaseThatIsNotAWrapIsTreatedAsResetAndContributesZero() {
        // An interface re-attached mid-range: counter dropped from 3 MB to 10 B.
        XCTAssertEqual(CounterDelta.bytes(previous: 3_000_000, current: 10, bitWidth: 32), 0)
        // 64-bit counters never wrap in practice, so any decrease is a reset.
        XCTAssertEqual(CounterDelta.bytes(previous: 50, current: 10, bitWidth: 64), 0)
    }

    func testRatesSumMatchedInterfacesOverInterval() throws {
        let old = [InterfaceCounters(name: "en0", receivedBytes: 1_000, sentBytes: 500),
                   InterfaceCounters(name: "en1", receivedBytes: 0, sentBytes: 0)]
        let new = [InterfaceCounters(name: "en0", receivedBytes: 5_000, sentBytes: 1_500),
                   InterfaceCounters(name: "en1", receivedBytes: 2_000, sentBytes: 0)]
        let rates = try XCTUnwrap(CounterDelta.rates(previous: old, current: new, interval: 2))
        XCTAssertEqual(rates.received, 3_000, accuracy: 0.001)
        XCTAssertEqual(rates.sent, 500, accuracy: 0.001)
        XCTAssertEqual(rates.receivedBytes, 6_000)
    }

    func testNewlyAttachedInterfaceDoesNotSpike() throws {
        let old = [InterfaceCounters(name: "en0", receivedBytes: 1_000, sentBytes: 1_000)]
        let new = [InterfaceCounters(name: "en0", receivedBytes: 1_100, sentBytes: 1_000),
                   InterfaceCounters(name: "en5", receivedBytes: 900_000_000, sentBytes: 900_000_000)]
        let rates = try XCTUnwrap(CounterDelta.rates(previous: old, current: new, interval: 1))
        XCTAssertEqual(rates.received, 100, accuracy: 0.001)
        XCTAssertEqual(rates.sent, 0, accuracy: 0.001)
    }

    func testInterfaceResetInsideRatesContributesZero() throws {
        let old = [InterfaceCounters(name: "en0", receivedBytes: 80_000_000, sentBytes: 40_000_000)]
        let new = [InterfaceCounters(name: "en0", receivedBytes: 1_024, sentBytes: 512)]
        let rates = try XCTUnwrap(CounterDelta.rates(previous: old, current: new, interval: 1))
        XCTAssertEqual(rates.received, 0)
        XCTAssertEqual(rates.sent, 0)
    }

    func testZeroIntervalHasNoRate() {
        XCTAssertNil(CounterDelta.rates(previous: [], current: [], interval: 0))
    }

    func testOnlyPhysicalInterfacesCountTowardThroughput() {
        XCTAssertTrue(CounterDelta.countsTowardThroughput("en0"))
        XCTAssertTrue(CounterDelta.countsTowardThroughput("pdp_ip0"))
        for name in ["lo0", "utun3", "awdl0", "llw0", "bridge0", "ipsec0"] {
            XCTAssertFalse(CounterDelta.countsTowardThroughput(name), name)
        }
    }

    func testLiveSnapshotCarriesNetworkAndPerCoreAfterSecondSample() async throws {
        let monitor = SystemMonitor()
        let first = try await monitor.snapshot()
        XCTAssertNil(first.cpuCorePercents)
        XCTAssertNil(first.network?.receivedBytesPerSecond)
        try await Task.sleep(for: .milliseconds(200))
        let second = try await monitor.snapshot()
        let cores = try XCTUnwrap(second.cpuCorePercents)
        XCTAssertEqual(cores.count, second.logicalCPUCount)
        XCTAssertTrue(cores.allSatisfy { (0...100).contains($0) })
        XCTAssertNotNil(second.network?.receivedBytesPerSecond)
        XCTAssertEqual(second.loadAverages?.count, 3)
    }
}

final class PerCoreCPUTests: XCTestCase {
    func testPerCoreBusyShareIncludesNiceAndSystem() throws {
        let old = [SystemCPUTicks(user: 0, system: 0, idle: 0, nice: 0),
                   SystemCPUTicks(user: 100, system: 100, idle: 100, nice: 100)]
        let new = [SystemCPUTicks(user: 30, system: 10, idle: 50, nice: 10),
                   SystemCPUTicks(user: 100, system: 100, idle: 200, nice: 100)]
        let cores = try XCTUnwrap(SystemCPUDelta.perCore(previous: old, current: new))
        XCTAssertEqual(cores[0], 50, accuracy: 0.0001)
        XCTAssertEqual(cores[1], 0, accuracy: 0.0001)
    }

    func testPerCoreHandlesRolloverAndParkedCores() throws {
        let old = [SystemCPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0),
                   SystemCPUTicks(user: 7, system: 7, idle: 7, nice: 7)]
        let new = [SystemCPUTicks(user: 10, system: 0, idle: 20, nice: 0),
                   SystemCPUTicks(user: 7, system: 7, idle: 7, nice: 7)]
        let cores = try XCTUnwrap(SystemCPUDelta.perCore(previous: old, current: new))
        XCTAssertEqual(cores[0], 50, accuracy: 0.0001)
        XCTAssertEqual(cores[1], 0)
    }

    func testPerCoreUnavailableWhenCPUSetChanges() {
        let ticks = [SystemCPUTicks(user: 1, system: 1, idle: 1, nice: 0)]
        XCTAssertNil(SystemCPUDelta.perCore(previous: nil, current: ticks))
        XCTAssertNil(SystemCPUDelta.perCore(previous: ticks + ticks, current: ticks))
    }
}

final class MenuBarPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = temporaryDefaults()
    }


    func testFreshInstallUsesGroupedDefaults() {
        let preferences = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(preferences.layout, .grouped)
        XCTAssertEqual(preferences.groupedStyle, .dial)
        XCTAssertEqual(preferences.groupedMetric, .cpu)
        XCTAssertTrue(preferences.groupedBadge)
        XCTAssertEqual(preferences.order, MenuBarModule.allCases)
        // The everyday tabs; the clipboard tab still appears only while clipboard history is on.
        XCTAssertEqual(preferences.enabledModules, [.overview, .cpu, .memory, .network, .clipboard])
        XCTAssertEqual(preferences.settings(for: .network).value, .networkUpDown)
        XCTAssertTrue(preferences.visible)
    }

    func testGroupedLayoutPlacesEachModuleInTheGroupOrInItsOwnItem() {
        var preferences = MenuBarPreferences(enabled: [.cpu, .memory, .weather, .clipboard])
        // Defaults: metrics and popover pages live in the group, status modules get their own item.
        XCTAssertEqual(preferences.items(), MenuBarItems(showsGroupedItem: true, modules: [.weather]))

        preferences.ownItems.insert(.memory)
        preferences.ownItems.remove(.weather)
        XCTAssertEqual(preferences.items(), MenuBarItems(showsGroupedItem: true, modules: [.memory]))
        // Placement applies to enabled modules only, in menu bar order.
        preferences.ownItems.insert(.disk)
        preferences.order = [.memory, .cpu]
        preferences.ownItems.insert(.cpu)
        XCTAssertEqual(preferences.items().modules, [.memory, .cpu])
        XCTAssertEqual(preferences.items(available: { $0 != .memory }).modules, [.cpu])
    }

    func testSeparateLayoutGivesEveryModuleItsOwnItem() {
        let preferences = MenuBarPreferences(layout: .separate, enabled: [.cpu, .weather])
        XCTAssertEqual(preferences.items(), MenuBarItems(showsGroupedItem: false, modules: [.cpu, .weather]))
        // With nothing enabled the grouped glyph stays, so MacPocket is always reachable.
        XCTAssertEqual(MenuBarPreferences(layout: .separate, enabled: []).items(), MenuBarItems(showsGroupedItem: true, modules: []))
        XCTAssertEqual(MenuBarPreferences(visible: false).items(), MenuBarItems(showsGroupedItem: false, modules: []))
    }

    func testOwnItemsRoundTripAndDefault() {
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).ownItems,
                       Set(MenuBarModule.allCases.filter(\.keepsOwnItemWhenGrouped)))
        var preferences = MenuBarPreferences.load(from: defaults)
        preferences.ownItems = [.cpu, .clock]
        preferences.save(to: defaults)
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).ownItems, [.cpu, .clock])
        preferences.ownItems = []
        preferences.save(to: defaults)
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).ownItems, [])
    }

    func testMigratesLegacySeparateLayoutAndOptions() {
        defaults.set("separate", forKey: "MacPocket.bar.layout")
        defaults.set("gaugeOnly", forKey: "MacPocket.bar.style")
        defaults.set(false, forKey: "MacPocket.bar.labels")
        defaults.set(true, forKey: "MacPocket.bar.icons")
        defaults.set(true, forKey: "MacPocket.bar.decimals")
        defaults.set("used", forKey: "MacPocket.bar.memoryValue")
        defaults.set(true, forKey: "MacPocket.bar.memoryPercent")
        defaults.set(true, forKey: "MacPocket.bar.diskPercent")
        defaults.set("/Volumes/Data", forKey: "MacPocket.bar.volume")
        defaults.set("battery,disk,cpu,memory,power", forKey: "MacPocket.bar.order")
        defaults.set(true, forKey: "MacPocket.bar.memory")
        defaults.set(true, forKey: "MacPocket.bar.battery")
        defaults.set(false, forKey: "MacPocket.menuBarCPU")

        let preferences = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(preferences.layout, .separate)
        XCTAssertEqual(preferences.order, [.overview, .power, .disk, .cpu, .memory, .gpu, .network, .weather, .aiUsage, .awake, .bluetooth, .display, .clock, .clipboard, .health, .timeline, .launcher])
        XCTAssertEqual(preferences.enabledModules, [.overview, .power, .memory, .clipboard])

        let memory = preferences.settings(for: .memory)
        XCTAssertEqual(memory.style, .gauge)
        XCTAssertFalse(memory.showValue)
        XCTAssertFalse(memory.showLabel)
        XCTAssertTrue(memory.showIcon)
        XCTAssertTrue(memory.decimals)
        XCTAssertEqual(memory.value, .memoryUsedPercent)

        let disk = preferences.settings(for: .disk)
        XCTAssertEqual(disk.value, .diskUsedPercent)
        XCTAssertEqual(disk.volumePath, "/Volumes/Data")
        XCTAssertEqual(preferences.settings(for: .power).value, .powerBattery)
        XCTAssertNil(defaults.object(forKey: "MacPocket.bar.battery"))
    }

    func testMigrationKeepsOldDefaultOfCPUOnly() {
        defaults.set("combined", forKey: "MacPocket.bar.layout")
        let preferences = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(preferences.layout, .grouped)
        XCTAssertEqual(preferences.enabledModules, [.overview, .cpu, .clipboard])
        XCTAssertEqual(preferences.settings(for: .memory).value, .memoryUsedBytes)
        XCTAssertEqual(preferences.settings(for: .disk).value, .diskFreeBytes)
    }

    func testMigrationRunsOnlyOnce() {
        defaults.set("separate", forKey: "MacPocket.bar.layout")
        _ = MenuBarPreferences.load(from: defaults)
        var preferences = MenuBarPreferences.load(from: defaults)
        preferences.layout = .grouped
        preferences.save(to: defaults)
        // A leftover legacy key must not override the user's new choice on the next launch.
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).layout, .grouped)
    }

    func testSaveLoadRoundTripPerModuleSettings() {
        var preferences = MenuBarPreferences.load(from: defaults)
        preferences.layout = .separate
        preferences.groupedStyle = .ring
        preferences.groupedMetric = .power
        preferences.groupedBadge = false
        preferences.order = [.network, .cpu]
        preferences.enabled = [.network, .disk]
        preferences.binaryUnits = false
        preferences.modules[.network] = MenuBarModuleSettings(style: .graph, showLabel: true, showIcon: true,
                                                              showValue: false, decimals: true, value: .networkCombined)
        preferences.modules[.disk] = MenuBarModuleSettings(value: .diskFreePercent, volumePath: "/")
        preferences.save(to: defaults)

        let loaded = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(loaded.layout, .separate)
        XCTAssertEqual(loaded.groupedStyle, .ring)
        XCTAssertEqual(loaded.groupedMetric, .power)
        XCTAssertFalse(loaded.groupedBadge)
        XCTAssertEqual(loaded.order, [.overview, .network, .cpu, .gpu, .memory, .disk, .power, .weather, .aiUsage, .awake, .bluetooth, .display, .clock, .clipboard, .health, .timeline, .launcher])
        XCTAssertEqual(loaded.enabledModules, [.network, .disk])
        XCTAssertFalse(loaded.binaryUnits)
        XCTAssertEqual(loaded.settings(for: .network), preferences.modules[.network])
        XCTAssertEqual(loaded.settings(for: .disk).volumePath, "/")
        XCTAssertEqual(defaults.object(forKey: "MacPocket.menuBarCPU") as? Bool, false)
    }

    func testRetiredWideGroupedStylesBecomeTheLiveDial() {
        defaults.set(MenuBarPreferences.schemaVersion, forKey: MenuBarPreferences.schemaKey)
        for retired in ["stacked", "gauges"] {
            defaults.set(retired, forKey: MenuBarPreferences.groupedStyleKey)
            XCTAssertEqual(MenuBarPreferences.load(from: defaults).groupedStyle, .dial, retired)
        }
    }

    func testStoredGlyphStyleStillMeansTheStaticIcon() {
        defaults.set(MenuBarPreferences.schemaVersion, forKey: MenuBarPreferences.schemaKey)
        defaults.set("glyph", forKey: MenuBarPreferences.groupedStyleKey)
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).groupedStyle, .symbol)
    }

    func testLegacyMigrationKeepsTheGroupedIconLive() {
        defaults.set("combined", forKey: "MacPocket.bar.layout")
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).groupedStyle, .dial)
    }

    func testValueOutsideModuleOptionsFallsBackToDefault() throws {
        let data = try JSONEncoder().encode(MenuBarModuleSettings(value: .networkUpload))
        defaults.set(data, forKey: MenuBarPreferences.moduleKey(.cpu))
        defaults.set(MenuBarPreferences.schemaVersion, forKey: MenuBarPreferences.schemaKey)
        XCTAssertEqual(MenuBarPreferences.load(from: defaults).settings(for: .cpu).value, .cpuTotal)
    }

    func testNewAppearanceOptionsRoundTrip() {
        var preferences = MenuBarPreferences.load(from: defaults)
        preferences.groupedStyle = .sparkline
        preferences.groupedAccent = .purple
        preferences.modules[.network] = MenuBarModuleSettings(style: .graph, value: .networkCombined, graphKind: .area, graphWidth: .wide,
                                                              textSize: .large, labelPosition: .beside, accent: .teal)
        preferences.save(to: defaults)
        let loaded = MenuBarPreferences.load(from: defaults)
        XCTAssertEqual(loaded.groupedStyle, .sparkline)
        XCTAssertEqual(loaded.groupedAccent, .purple)
        XCTAssertEqual(loaded.settings(for: .network), preferences.modules[.network])
    }

    func testStoredSettingsFromBeforeTheNewOptionsKeepWorking() throws {
        let legacy = #"{"style":"graph","showLabel":false,"value":"cpuUser","colorMode":"thresholds"}"#
        let settings = try JSONDecoder().decode(MenuBarModuleSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(settings.graphKind, .bars)
        XCTAssertEqual(settings.graphWidth, .standard)
        XCTAssertEqual(settings.textSize, .regular)
        XCTAssertEqual(settings.labelPosition, .automatic)
        XCTAssertEqual(settings.accent, .automatic)
    }

    func testEveryModuleOffersOnlyStylesItCanDraw() {
        for module in MenuBarModule.allCases {
            XCTAssertTrue(module.styleOptions.contains(.value), module.rawValue)
            XCTAssertEqual(Set(module.styleOptions).count, module.styleOptions.count, module.rawValue)
            XCTAssertEqual(module.styleOptions.contains(.cores), module == .cpu, module.rawValue)
        }
    }

    func testWarningCannotPassCriticalWhenHigherIsWorse() {
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        settings.setCriticalThreshold(80)
        settings.setWarningThreshold(95)
        let limits = settings.thresholds
        XCTAssertEqual(limits?.critical, 80)
        XCTAssertEqual(limits?.warning, 79)
        settings.setCriticalThreshold(10)
        XCTAssertEqual(settings.thresholds?.critical, 80)
    }

    func testCriticalCannotPassWarningWhenLowerIsWorse() {
        var settings = MenuBarModuleSettings.defaults(for: .power)
        XCTAssertEqual(settings.thresholds?.warning, 20)
        settings.setWarningThreshold(5)
        XCTAssertEqual(settings.thresholds?.warning, 11)
        settings.setCriticalThreshold(60)
        XCTAssertEqual(settings.thresholds?.critical, 10)
    }

    func testThresholdsStayInsideTheUnitRange() {
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        settings.setCriticalThreshold(500)
        XCTAssertEqual(settings.thresholds?.critical, 100)
        settings.setWarningThreshold(-20)
        XCTAssertEqual(settings.thresholds?.warning, 0)
    }

    func testDecodingToleratesMissingFields() throws {
        let settings = try JSONDecoder().decode(MenuBarModuleSettings.self, from: Data(#"{"value":"diskActivity"}"#.utf8))
        XCTAssertEqual(settings.value, .diskActivity)
        XCTAssertEqual(settings.style, .value)
        XCTAssertTrue(settings.showValue)
    }
}

final class MenuBarFormatterTests: XCTestCase {
    private func snapshot(network: NetworkSnapshot? = nil, battery: Bool = false) -> SystemSnapshot {
        var snapshot = SystemSnapshot(
            capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 2,
            cpuUserPercent: 8.4, cpuSystemPercent: 4.2, cpuIdlePercent: 87.4,
            physicalMemoryBytes: 16 << 30, freeMemoryBytes: 1 << 30, wiredMemoryBytes: 2 << 30,
            compressedMemoryBytes: 1 << 30, appMemoryBytes: 5 << 30, swapUsedBytes: 0, uptimeSeconds: 100,
            thermalState: "nominal",
            volumes: [VolumeSnapshot(name: "Data", path: "/Volumes/Data", totalBytes: 1_000, availableBytes: 750),
                      VolumeSnapshot(name: "Macintosh HD", path: "/", totalBytes: 500 << 30, availableBytes: 125 << 30)],
            power: PowerSnapshot(source: battery ? "Battery Power" : "AC Power", batteryPresent: battery,
                                 chargePercent: battery ? 81 : nil, isCharging: battery ? false : nil, lowPowerMode: false))
        snapshot.network = network
        snapshot.memoryPressurePercent = 23
        return snapshot
    }

    func testNumberFormattingIsTurkish() {
        XCTAssertEqual(MenuBarFormatter.percent(12.46, decimals: false), "%12")
        XCTAssertEqual(MenuBarFormatter.percent(12.46, decimals: true), "%12,5")
        XCTAssertEqual(MenuBarFormatter.percent(140, decimals: false), "%100")
        XCTAssertEqual(MenuBarFormatter.bytes(1_288_490_189, binary: true), "1,2 GB")
        XCTAssertEqual(MenuBarFormatter.bytes(18 * 1_073_741_824, binary: true), "18 GB")
        XCTAssertEqual(MenuBarFormatter.bytes(512, binary: true), "512 B")
        XCTAssertEqual(MenuBarFormatter.bytes(1_500_000_000, binary: false), "1,5 GB")
        XCTAssertEqual(MenuBarFormatter.rate(0, binary: true), "0 KB/s")
        XCTAssertEqual(MenuBarFormatter.rate(86_016, binary: true), "84 KB/s")
        XCTAssertEqual(MenuBarFormatter.rate(1_258_291, binary: true), "1,2 MB/s")
        XCTAssertEqual(MenuBarFormatter.rate(nil, binary: true), "— KB/s")
        XCTAssertEqual(MenuBarFormatter.duration(minutes: 135), "2:15")
        XCTAssertEqual(MenuBarFormatter.duration(minutes: 42), "42 dk")
    }

    func testCPUValueChoices() {
        let s = snapshot()
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        let total = MenuBarFormatter.reading(.cpu, settings: settings, snapshot: s)
        XCTAssertEqual(total.lines, ["%13"])
        XCTAssertEqual(total.fraction ?? 0, 0.126, accuracy: 0.0001)
        XCTAssertEqual(total.accessibility, "CPU: %13 kullanım")
        settings.value = .cpuSystem
        settings.decimals = true
        XCTAssertEqual(MenuBarFormatter.reading(.cpu, settings: settings, snapshot: s).lines, ["%4,2"])
    }

    func testMemoryValueChoices() {
        let s = snapshot()
        var settings = MenuBarModuleSettings.defaults(for: .memory)
        XCTAssertEqual(MenuBarFormatter.reading(.memory, settings: settings, snapshot: s).lines, ["%50"])
        settings.value = .memoryUsedBytes
        XCTAssertEqual(MenuBarFormatter.reading(.memory, settings: settings, snapshot: s).lines, ["8,0 GB"])
        settings.value = .memoryFreeBytes
        XCTAssertEqual(MenuBarFormatter.reading(.memory, settings: settings, snapshot: s).lines, ["8,0 GB"])
        settings.value = .memoryPressure
        XCTAssertEqual(MenuBarFormatter.reading(.memory, settings: settings, snapshot: s).lines, ["%23"])
    }

    func testDiskUsesStartupVolumeByDefaultAndSelectedVolumeOtherwise() {
        let s = snapshot()
        var settings = MenuBarModuleSettings.defaults(for: .disk)
        XCTAssertEqual(MenuBarFormatter.reading(.disk, settings: settings, snapshot: s).lines, ["125 GB"])
        settings.value = .diskUsedPercent
        XCTAssertEqual(MenuBarFormatter.reading(.disk, settings: settings, snapshot: s).lines, ["%75"])
        settings.volumePath = "/Volumes/Data"
        settings.value = .diskFreePercent
        let reading = MenuBarFormatter.reading(.disk, settings: settings, snapshot: s)
        XCTAssertEqual(reading.lines, ["%75"])
        XCTAssertEqual(reading.fraction ?? 0, 0.25, accuracy: 0.0001)
        settings.volumePath = "/Volumes/Missing"
        XCTAssertEqual(MenuBarFormatter.reading(.disk, settings: settings, snapshot: s).lines, ["—"])
    }

    func testNetworkValueChoices() {
        let network = NetworkSnapshot(receivedBytesPerSecond: 1_258_291, sentBytesPerSecond: 2_048,
                                      primaryInterface: "en0", localIPv4: "192.168.1.4")
        let s = snapshot(network: network)
        var settings = MenuBarModuleSettings.defaults(for: .network)
        let stacked = MenuBarFormatter.reading(.network, settings: settings, snapshot: s)
        XCTAssertEqual(stacked.lines, ["↑ 2 KB/s", "↓ 1,2 MB/s"])
        XCTAssertEqual(stacked.reserve.count, 2)
        XCTAssertNil(stacked.fraction)
        settings.value = .networkCombined
        XCTAssertEqual(MenuBarFormatter.reading(.network, settings: settings, snapshot: s).lines, ["1,2 MB/s"])
        settings.value = .networkDownload
        XCTAssertEqual(MenuBarFormatter.reading(.network, settings: settings, snapshot: s).lines, ["↓ 1,2 MB/s"])
        let first = MenuBarFormatter.reading(.network, settings: .defaults(for: .network), snapshot: snapshot())
        XCTAssertEqual(first.lines, ["↑ — KB/s", "↓ — KB/s"])
    }

    func testPowerFallsBackToSourceWithoutBattery() {
        var settings = MenuBarModuleSettings.defaults(for: .power)
        XCTAssertEqual(MenuBarFormatter.reading(.power, settings: settings, snapshot: snapshot()).lines, ["Priz"])
        let battery = MenuBarFormatter.reading(.power, settings: settings, snapshot: snapshot(battery: true))
        XCTAssertEqual(battery.lines, ["%81"])
        XCTAssertEqual(battery.accessibility, "Pil: %81")
        settings.value = .powerTimeRemaining
        var s = snapshot(battery: true)
        XCTAssertEqual(MenuBarFormatter.reading(.power, settings: settings, snapshot: s).lines, ["%81"])
        s = SystemSnapshot(capturedAt: s.capturedAt, hardwareModel: s.hardwareModel, logicalCPUCount: 2,
                           cpuUserPercent: nil, cpuSystemPercent: nil, cpuIdlePercent: nil,
                           physicalMemoryBytes: 1, freeMemoryBytes: 0, wiredMemoryBytes: 0, compressedMemoryBytes: 0,
                           uptimeSeconds: 0, thermalState: "nominal", volumes: [],
                           power: {
                               var power = s.power
                               power.minutesRemaining = 95
                               return power
                           }())
        XCTAssertEqual(MenuBarFormatter.reading(.power, settings: settings, snapshot: s).lines, ["1:35"])
    }

    func testLoadAverageIsShownPerCoreForColoring() throws {
        var current = snapshot()
        current.loadAverages = [1.5, 1.2, 1.0]
        var settings = MenuBarModuleSettings.defaults(for: .cpu)
        settings.value = .cpuLoad
        let reading = MenuBarFormatter.reading(.cpu, settings: settings, snapshot: current)
        XCTAssertEqual(reading.lines, [MenuBarFormatter.number(1.5, fractionDigits: 2)])
        XCTAssertEqual(try XCTUnwrap(reading.fraction), 0.75, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reading.thresholdValue), 75, accuracy: 0.01)
    }

    func testSwapShowsUsedBytesAndShareOfTheSwapFile() throws {
        var current = snapshot()
        current.swapUsedBytes = 1 << 30
        current.swapTotalBytes = 4 << 30
        var settings = MenuBarModuleSettings.defaults(for: .memory)
        settings.value = .memorySwap
        let reading = MenuBarFormatter.reading(.memory, settings: settings, snapshot: current)
        XCTAssertEqual(try XCTUnwrap(reading.fraction), 0.25, accuracy: 0.001)
        XCTAssertTrue(reading.lines[0].contains("GB"))
    }

    func testPowerDrawIsShownInWattsOrAsUnavailable() {
        var current = snapshot()
        var settings = MenuBarModuleSettings.defaults(for: .power)
        settings.value = .powerWatts
        XCTAssertEqual(MenuBarFormatter.reading(.power, settings: settings, snapshot: current).lines, ["—"])
        current.systemPowerWatts = 42.4
        let reading = MenuBarFormatter.reading(.power, settings: settings, snapshot: current)
        XCTAssertEqual(reading.lines, [MenuBarFormatter.number(42.4, fractionDigits: 0) + " W"])
        XCTAssertEqual(reading.fraction ?? 0, 0.424, accuracy: 0.001)
    }

    func testEveryValueOfEveryModuleProducesAReadingWithoutData() {
        for module in MenuBarModule.allCases {
            for value in module.valueOptions {
                var settings = MenuBarModuleSettings.defaults(for: module)
                settings.value = value
                XCTAssertFalse(MenuBarFormatter.reading(module, settings: settings, snapshot: nil).lines.isEmpty, "\(module) \(value)")
                XCTAssertFalse(MenuBarFormatter.reading(module, settings: settings, snapshot: snapshot()).lines.isEmpty, "\(module) \(value)")
            }
        }
    }

    func testClockShowsTheTimeInTheChosenZone() {
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(MenuBarFormatter.clockReading(value: .clockTime, zoneID: "UTC", now: now, locale: locale).lines, ["22:13"])
        XCTAssertEqual(MenuBarFormatter.clockReading(value: .clockTime, zoneID: "Europe/Istanbul", now: now, locale: locale).lines, ["01:13"])
        XCTAssertEqual(MenuBarFormatter.clockReading(value: .clockTimeSeconds, zoneID: "Asia/Tokyo", now: now, locale: locale).lines, ["07:13:20"])
        XCTAssertTrue(MenuBarFormatter.clockReading(value: .clockWeekdayTime, zoneID: "UTC", now: now, locale: locale).lines[0].contains("Tue"))
        XCTAssertTrue(MenuBarFormatter.clockReading(value: .clockDateTime, zoneID: "UTC", now: now, locale: locale).lines[0].contains("14"))
    }

    func testClockFallsBackToThisMacForUnknownZones() {
        let reading = MenuBarFormatter.clockReading(value: .clockTime, zoneID: "Not/AZone", now: Date(), locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(reading.lines.count, 1)
        XCTAssertFalse(reading.lines[0].isEmpty)
    }

    func testClockCityNames() {
        XCTAssertEqual(MenuBarFormatter.cityName("America/New_York"), "New York")
        XCTAssertEqual(MenuBarFormatter.cityName("UTC"), "UTC")
        for zone in MenuBarFormatter.commonTimeZones { XCTAssertNotNil(TimeZone(identifier: zone), zone) }
    }

    func testWorldClocksSurviveSaveAndLoad() throws {
        let data = try JSONEncoder().encode(MenuBarModuleSettings(value: .clockTime, timeZoneID: "Asia/Tokyo", worldClocks: ["UTC", "Europe/London"]))
        let decoded = try JSONDecoder().decode(MenuBarModuleSettings.self, from: data)
        XCTAssertEqual(decoded.timeZoneID, "Asia/Tokyo")
        XCTAssertEqual(decoded.worldClocks, ["UTC", "Europe/London"])
    }

    func testMissingSnapshotShowsPlaceholder() {
        let reading = MenuBarFormatter.reading(.cpu, settings: .defaults(for: .cpu), snapshot: nil)
        XCTAssertEqual(reading.lines, ["—"])
        XCTAssertEqual(reading.accessibility, "CPU: ölçüm bekleniyor")
    }
}
