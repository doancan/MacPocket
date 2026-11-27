import XCTest
@testable import MacPocketCore
import MacPocketTestSupport

final class AppPreferencesTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let store = temporaryDefaultsStore()
        return (store.defaults, store.suiteName)
    }

    // MARK: Language

    func testLanguageMapsAppleLanguages() {
        XCTAssertEqual(AppLanguage(appleLanguages: nil), .system)
        XCTAssertEqual(AppLanguage(appleLanguages: []), .system)
        XCTAssertEqual(AppLanguage(appleLanguages: ["tr"]), .turkish)
        XCTAssertEqual(AppLanguage(appleLanguages: ["tr-TR", "en"]), .turkish)
        XCTAssertEqual(AppLanguage(appleLanguages: ["en-GB"]), .english)
        XCTAssertEqual(AppLanguage(appleLanguages: ["de"]), .system)
        XCTAssertNil(AppLanguage.system.appleLanguages)
        XCTAssertEqual(AppLanguage.turkish.appleLanguages, ["tr"])
        XCTAssertEqual(AppLanguage.english.appleLanguages, ["en"])
    }

    func testLanguageRoundTripsThroughAppDomain() {
        let (defaults, domain) = defaults()
        XCTAssertEqual(AppLanguage.load(from: defaults, domain: domain), .system)
        AppLanguage.english.save(to: defaults)
        XCTAssertEqual(AppLanguage.load(from: defaults, domain: domain), .english)
        AppLanguage.turkish.save(to: defaults)
        XCTAssertEqual(AppLanguage.load(from: defaults, domain: domain), .turkish)
        AppLanguage.system.save(to: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: domain)?[AppLanguage.defaultsKey])
        XCTAssertEqual(AppLanguage.load(from: defaults, domain: domain), .system)
    }

    func testPinnedLanguageAlignsLocaleKeepingRegionAndKeywords() {
        XCTAssertEqual(AppLanguage.turkish.appleLocale(systemLocale: "en_TR"), "tr_TR")
        XCTAssertEqual(AppLanguage.english.appleLocale(systemLocale: "tr_TR"), "en_TR")
        XCTAssertEqual(AppLanguage.english.appleLocale(systemLocale: "de_DE@calendar=buddhist"), "en_DE@calendar=buddhist")
        XCTAssertNil(AppLanguage.system.appleLocale(systemLocale: "en_TR"))
        XCTAssertNil(AppLanguage.turkish.appleLocale(systemLocale: nil))
        // The aligned identifier is what makes the app's current locale speak the pinned language.
        XCTAssertEqual(Locale(identifier: AppLanguage.turkish.appleLocale(systemLocale: "en_TR")!).language.languageCode, "tr")
    }

    func testLocaleOverrideFollowsLanguageChoice() {
        let (defaults, domain) = defaults()
        AppLanguage.turkish.save(to: defaults, systemLocale: "en_TR")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.localeKey), "tr_TR")
        AppLanguage.english.save(to: defaults, systemLocale: "en_TR")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.localeKey), "en_TR")
        // A changed system region is picked up by the launch-time alignment.
        AppLanguage.english.alignLocale(in: defaults, systemLocale: "en_GB")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.localeKey), "en_GB")
        AppLanguage.system.save(to: defaults, systemLocale: "en_TR")
        // Read the suite's own domain: `object(forKey:)` would fall through to the global AppleLocale.
        XCTAssertNil(defaults.persistentDomain(forName: domain)?[AppLanguage.localeKey])
        XCTAssertNil(defaults.persistentDomain(forName: domain)?[AppLanguage.defaultsKey])
    }

    // MARK: Settings transfer

    func testTransferableKeys() {
        XCTAssertTrue(SettingsTransfer.isTransferable("MacPocket.appearance"))
        XCTAssertTrue(SettingsTransfer.isTransferable("switcher.style"))
        XCTAssertFalse(SettingsTransfer.isTransferable("MacPocket."))
        XCTAssertFalse(SettingsTransfer.isTransferable("AppleLanguages"))
        XCTAssertFalse(SettingsTransfer.isTransferable("manager.showUser"))
        XCTAssertFalse(SettingsTransfer.isTransferable("NSWindow Frame main"))
    }

    func testExportImportRoundTripFiltersKeys() throws {
        let (source, sourceDomain) = defaults()
        source.set("dark", forKey: "MacPocket.appearance")
        source.set(5.0, forKey: "MacPocket.refreshSeconds")
        source.set(true, forKey: "switcher.globalEnabled")
        source.set(["/Applications/A.app"], forKey: "switcher.excludedPaths")
        source.set(Data([1, 2, 3]), forKey: "switcher.shortcut")
        source.set(["en"], forKey: "AppleLanguages")
        source.set("x", forKey: "OtherApp.key")

        let data = try SettingsTransfer.exportData(from: SettingsTransfer.currentValues(source, domain: sourceDomain))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("AppleLanguages"))
        XCTAssertFalse(text.contains("OtherApp"))

        let (target, targetDomain) = defaults()
        target.set("light", forKey: "MacPocket.appearance")
        target.set(true, forKey: "MacPocket.stale")
        target.set("keep", forKey: "Unrelated.key")
        SettingsTransfer.apply(try SettingsTransfer.importValues(from: data), to: target, domain: targetDomain)

        XCTAssertEqual(target.string(forKey: "MacPocket.appearance"), "dark")
        XCTAssertEqual(target.double(forKey: "MacPocket.refreshSeconds"), 5)
        XCTAssertTrue(target.bool(forKey: "switcher.globalEnabled"))
        XCTAssertEqual(target.stringArray(forKey: "switcher.excludedPaths"), ["/Applications/A.app"])
        XCTAssertEqual(target.data(forKey: "switcher.shortcut"), Data([1, 2, 3]))
        XCTAssertNil(target.object(forKey: "MacPocket.stale"), "keys missing from the file reset to defaults")
        XCTAssertEqual(target.string(forKey: "Unrelated.key"), "keep")
        XCTAssertNil(target.persistentDomain(forName: targetDomain)?["OtherApp.key"])
    }

    func testImportIgnoresForeignKeysAndRejectsOtherFiles() throws {
        let json = #"{"format":"MacPocket.settings","version":1,"values":{"MacPocket.a":1,"AppleLanguages":["en"],"evil":"x"}}"#
        let values = try SettingsTransfer.importValues(from: Data(json.utf8))
        XCTAssertEqual(Set(values.keys), ["MacPocket.a"])
        XCTAssertThrowsError(try SettingsTransfer.importValues(from: Data("nope".utf8))) {
            XCTAssertEqual($0 as? SettingsTransferError, .unreadable)
        }
        XCTAssertThrowsError(try SettingsTransfer.importValues(from: Data(#"{"values":{}}"#.utf8))) {
            XCTAssertEqual($0 as? SettingsTransferError, .wrongFormat)
        }
        XCTAssertThrowsError(try SettingsTransfer.importValues(from: Data(#"{"format":"MacPocket.settings","version":9,"values":{}}"#.utf8))) {
            XCTAssertEqual($0 as? SettingsTransferError, .unsupportedVersion(9))
        }
    }

    func testResetRemovesOnlyMacPocketKeys() {
        let (defaults, domain) = defaults()
        defaults.set(1, forKey: "MacPocket.a")
        defaults.set(2, forKey: "switcher.b")
        defaults.set(3, forKey: "manager.c")
        SettingsTransfer.reset(defaults, domain: domain)
        XCTAssertNil(defaults.object(forKey: "MacPocket.a"))
        XCTAssertNil(defaults.object(forKey: "switcher.b"))
        XCTAssertEqual(defaults.integer(forKey: "manager.c"), 3)
    }

    // MARK: Alerts

    func testAlertThresholds() {
        let all = ResourceAlertSettings(enabled: Set(ResourceAlertKind.allCases), diskFreePercent: 10)
        XCTAssertEqual(ResourceAlertReading(diskFreePercent: 9.9, thermalState: "nominal", memoryPressureLevel: 1).triggered(all), [.lowDisk])
        XCTAssertEqual(ResourceAlertReading(diskFreePercent: 10, thermalState: "fair", memoryPressureLevel: 2).triggered(all), [])
        XCTAssertEqual(ResourceAlertReading(diskFreePercent: nil, thermalState: "serious", memoryPressureLevel: 4).triggered(all),
                       [.thermal, .memoryPressure])
        XCTAssertEqual(ResourceAlertReading(diskFreePercent: 50, thermalState: "critical", memoryPressureLevel: nil).triggered(all), [.thermal])
        let diskOnly = ResourceAlertSettings(enabled: [.lowDisk], diskFreePercent: 20)
        XCTAssertEqual(ResourceAlertReading(diskFreePercent: 15, thermalState: "critical", memoryPressureLevel: 4).triggered(diskOnly), [.lowDisk])
        XCTAssertEqual(ResourceAlertReading(diskFreePercent: 1, thermalState: "critical", memoryPressureLevel: 4).triggered(.init()), [])
    }

    func testSustainedThresholdMeasuresAnUnbrokenStreak() {
        var streak = SustainedThreshold()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(streak.update(90, threshold: 85, at: start), 0)
        XCTAssertEqual(streak.update(86, threshold: 85, at: start + 120), 120)
        XCTAssertNil(streak.update(40, threshold: 85, at: start + 180), "dropping below breaks the streak")
        XCTAssertEqual(streak.update(95, threshold: 85, at: start + 240), 0, "a new streak starts over")
        XCTAssertNil(streak.update(nil, threshold: 85, at: start + 300), "a missing sample breaks it too")
    }

    func testSustainedCPUAndLowBatteryAlerts() {
        let all = ResourceAlertSettings(enabled: Set(ResourceAlertKind.allCases), diskFreePercent: 10, cpuPercent: 85, cpuMinutes: 5,
                                        batteryPercent: 15)
        func reading(cpu: TimeInterval? = nil, battery: Double? = nil, discharging: Bool = false) -> ResourceAlertReading {
            ResourceAlertReading(diskFreePercent: 50, thermalState: "nominal", memoryPressureLevel: 1, cpuHighDuration: cpu,
                                 batteryPercent: battery, discharging: discharging)
        }
        XCTAssertEqual(reading(cpu: 299).triggered(all), [])
        XCTAssertEqual(reading(cpu: 300).triggered(all), [.sustainedCPU])
        XCTAssertEqual(reading(battery: 15, discharging: true).triggered(all), [.lowBattery])
        XCTAssertEqual(reading(battery: 10, discharging: false).triggered(all), [], "charging or on power: no alert")
        XCTAssertEqual(reading(battery: 16, discharging: true).triggered(all), [])
    }

    func testNewAlertThresholdsLoadWithDefaultsAndClamp() {
        let defaults = temporaryDefaults()
        XCTAssertEqual(ResourceAlertSettings.load(from: defaults).cpuMinutes, 5)
        defaults.set(500.0, forKey: ResourceAlertSettings.cpuThresholdKey)
        defaults.set(20.0, forKey: ResourceAlertSettings.batteryThresholdKey)
        let settings = ResourceAlertSettings.load(from: defaults)
        XCTAssertEqual(settings.cpuPercent, 100)
        XCTAssertEqual(settings.batteryPercent, 20)
    }

    func testAlertReadingUsesStartupVolume() {
        let snapshot = SystemSnapshot(capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 1, cpuUserPercent: nil,
                                      cpuSystemPercent: nil, cpuIdlePercent: nil, physicalMemoryBytes: 1, freeMemoryBytes: 1,
                                      wiredMemoryBytes: 0, compressedMemoryBytes: 0, uptimeSeconds: 1, thermalState: "nominal",
                                      volumes: [.init(name: "Ext", path: "/Volumes/Ext", totalBytes: 100, availableBytes: 90),
                                                .init(name: "Mac", path: "/", totalBytes: 200, availableBytes: 10)],
                                      power: .init(source: "AC Power", batteryPresent: false, chargePercent: nil, isCharging: nil, lowPowerMode: false))
        XCTAssertEqual(ResourceAlertReading(snapshot).diskFreePercent ?? -1, 5, accuracy: 0.001)
    }

    func testAlertLimiterSendsAtMostOncePerHour() {
        var limiter = ResourceAlertLimiter()
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(limiter.admit([.lowDisk], now: start), [.lowDisk])
        XCTAssertEqual(limiter.admit([.lowDisk], now: start.addingTimeInterval(60)), [])
        XCTAssertEqual(limiter.admit([.lowDisk, .thermal], now: start.addingTimeInterval(120)), [.thermal])
        XCTAssertEqual(limiter.admit([.lowDisk, .thermal], now: start.addingTimeInterval(3599)), [])
        XCTAssertEqual(limiter.admit([.lowDisk, .thermal], now: start.addingTimeInterval(3600)), [.lowDisk])
        XCTAssertEqual(limiter.admit([], now: start.addingTimeInterval(10_000)), [])
        XCTAssertEqual(limiter.admit([.thermal], now: start.addingTimeInterval(10_000)), [.thermal])
        // A clock moved backwards must not block alerts for the rest of the hour.
        XCTAssertEqual(limiter.admit([.memoryPressure], now: start), [.memoryPressure])
        XCTAssertEqual(limiter.admit([.memoryPressure], now: start.addingTimeInterval(-10)), [.memoryPressure])
    }

    func testAlertSettingsLoad() {
        let (defaults, _) = defaults()
        XCTAssertEqual(ResourceAlertSettings.load(from: defaults), ResourceAlertSettings())
        defaults.set(true, forKey: ResourceAlertSettings.enabledKey(.thermal))
        defaults.set(15.0, forKey: ResourceAlertSettings.diskThresholdKey)
        XCTAssertEqual(ResourceAlertSettings.load(from: defaults), ResourceAlertSettings(enabled: [.thermal], diskFreePercent: 15))
    }

    // MARK: History

    func testHistoryRetention() {
        let (defaults, _) = defaults()
        XCTAssertEqual(PowerHistoryRetention.days(from: defaults), 14)
        XCTAssertEqual(PowerHistoryRetention.maximumEntries(days: 14), 20_160)
        defaults.set(30, forKey: PowerHistoryRetention.key)
        XCTAssertEqual(PowerHistoryRetention.days(from: defaults), 30)
        defaults.set(3, forKey: PowerHistoryRetention.key)
        XCTAssertEqual(PowerHistoryRetention.days(from: defaults), 14)
    }

    func testClearingPowerHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPocket-clear-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let store = PowerHistoryStore(url: url)
        let snapshot = SystemSnapshot(capturedAt: Date(), hardwareModel: "fixture", logicalCPUCount: 1, cpuUserPercent: nil,
                                      cpuSystemPercent: nil, cpuIdlePercent: nil, physicalMemoryBytes: 1, freeMemoryBytes: 1,
                                      wiredMemoryBytes: 0, compressedMemoryBytes: 0, uptimeSeconds: 1, thermalState: "nominal",
                                      volumes: [], power: .init(source: "AC Power", batteryPresent: false, chargePercent: nil,
                                                                isCharging: nil, lowPowerMode: false))
        _ = try await store.record(snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try await store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let entries = try await store.entries()
        XCTAssertTrue(entries.isEmpty)
        let reloaded = try await PowerHistoryStore(url: url).entries()
        XCTAssertTrue(reloaded.isEmpty)
    }
}

final class ProcessCPUScaleTests: XCTestCase {
    func testWholeMacScaleDividesByCoreCount() {
        XCTAssertEqual(ProcessCPUScale.wholeMac.value(500, logicalCPUCount: 10), 50)
        XCTAssertEqual(ProcessCPUScale.wholeMac.value(1000, logicalCPUCount: 10), 100)
    }

    func testPerCoreScaleKeepsTheSample() {
        XCTAssertEqual(ProcessCPUScale.perCore.value(500, logicalCPUCount: 10), 500)
    }

    func testZeroCoreCountDoesNotDivideByZero() {
        XCTAssertEqual(ProcessCPUScale.wholeMac.value(80, logicalCPUCount: 0), 80)
    }

    func testLoadDefaultsToWholeMacAndIgnoresUnknownValues() throws {
        let defaults = temporaryDefaults()
        XCTAssertEqual(ProcessCPUScale.load(from: defaults), .wholeMac)
        defaults.set("linux", forKey: ProcessCPUScale.key)
        XCTAssertEqual(ProcessCPUScale.load(from: defaults), .wholeMac)
        defaults.set(ProcessCPUScale.perCore.rawValue, forKey: ProcessCPUScale.key)
        XCTAssertEqual(ProcessCPUScale.load(from: defaults), .perCore)
    }
}
