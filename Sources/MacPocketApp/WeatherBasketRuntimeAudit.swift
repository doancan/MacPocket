#if DEBUG
import AppKit
import ApplicationServices
import ObjectiveC
import MacPocketCore
import ScreenCaptureKit
import SwiftUI

/// Own settings suite, own Keychain namespace, public city coordinates and public anonymous APIs only.
@MainActor enum WeatherBasketRuntimeAudit {
    static var requested: Bool { CommandLine.arguments.contains("--audit-weather-basket") }
    static func configureIfRequested() {
        guard requested else { return }
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        values[PocketPreferenceKey.showWindowAtLaunch] = false
        for module in PocketModule.allCases { values[module.availabilityKey] = false }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }
    static func launch() {
        guard let index = CommandLine.arguments.firstIndex(of: "--audit-weather-basket"), CommandLine.arguments.indices.contains(index + 1) else { NSApp.terminate(nil); return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { await run(directory); NSApp.terminate(nil) }
    }
    private static func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<600 {
            if condition() { return true }; try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
    private static func press(_ label: String, in root: NSObject) async -> Bool {
        var pending = [root], seen = Set<ObjectIdentifier>()
        while let node = pending.popLast(), seen.count < 3_000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            let names = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue", "accessibilityDescription"].compactMap { name -> String? in
                let selector = NSSelectorFromString(name)
                return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
            }
            let selector = NSSelectorFromString("accessibilityPerformPress")
            if names.contains(where: { $0 == label }), node.responds(to: selector) {
                typealias Press = @convention(c) (AnyObject, Selector) -> ObjCBool
                let action = unsafeBitCast(node.method(for: selector), to: Press.self)
                if action(node, selector).boolValue {
                    try? await Task.sleep(for: .milliseconds(150))
                    return true
                }
            }
            if let window = node as? NSWindow, let content = window.contentView { pending.append(content) }
            if let view = node as? NSView { pending += view.subviews }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        guard let window = root as? NSWindow else { return false }
        let controls = [String(localized: "Hava Durumu Ayarları"): "weather.settings", String(localized: "Hava Durumuna Dön"): "weather.back",
            String(localized: "Open-Meteo modelleri"): "weather.models", String(localized: "Ücretsiz hesapla kullanılan kaynaklar"): "weather.accounts",
            String(localized: "API Anahtarı Ekle"): "weather.connect", String(localized: "Konum Seç"): "weather.choose-location",
            String(localized: "Sonraki Saatler"): "weather.hours.next", String(localized: "Önceki Saatler"): "weather.hours.previous",
            String(localized: "Saat Ayrıntısını Kapat"): "weather.hour-close"]
        let target = controls[label] ?? WeatherSource.allCases.first(where: { $0.localizedTitle == label }).map { "weather.source." + $0.rawValue }
        guard let target else { return false }
        return await WeatherUIProbe.click(target, in: window)
    }
    private static func capture(_ window: NSWindow, at destination: URL) async throws {
        guard WindowPreviewProvider.permitted else { throw WindowPreviewError.permissionRequired }
        try await Task.sleep(for: .milliseconds(300))
        // SwiftUI creates its AX bridge lazily on a client request. Query only this process off the
        // main thread, so the main run loop can answer it without deadlocking or requesting consent.
        if AXIsProcessTrusted() {
            let pid = getpid()
            _ = await Task.detached {
                var pending: [(AXUIElement, Int)] = [(AXUIElementCreateApplication(pid), 0)], count = 0
                while let (element, depth) = pending.popLast(), count < 600 {
                    count += 1
                    guard depth < 8 else { continue }
                    for key in [kAXWindowsAttribute, kAXChildrenAttribute] {
                        var value: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
                           let children = value as? [AXUIElement] { pending += children.map { ($0, depth + 1) } }
                    }
                }
                return count
            }.value
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { throw WindowPreviewError.unavailable }
        let filter = SCContentFilter(desktopIndependentWindow: target), configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)); configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw WindowPreviewError.unavailable }
        try data.write(to: destination)
    }
    private static func host<Content: View>(_ content: Content, in window: NSWindow, size: NSSize) {
        WeatherUIProbe.targets.removeAll()
        let controller = NSHostingController(rootView: content.frame(width: size.width, height: size.height, alignment: .topLeading).weatherAuditTarget("weather.root"))
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private static func run(_ directory: URL) async {
        let namespace = "com.doancan.MacPocket.weather.audit." + UUID().uuidString
        let preferences = UserDefaults(suiteName: namespace)!, keys = WeatherKeychainStore(namespace: namespace)
        let service = WeatherService(defaults: preferences, credentials: keys)
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 368, height: 590), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "MacPocket · Weather audit"
        window.appearance = NSAppearance(named: CommandLine.arguments.contains("--audit-dark") ? .darkAqua : .aqua)
        var checks: [String: Bool] = [:], failure: String?
        defer { service.setEnabled(false); window.close(); preferences.removePersistentDomain(forName: namespace); try? keys.save(nil, for: .weatherAPI) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try keys.save("owned-weather-fixture", for: .weatherAPI)
            let restoredKey = try keys.read(.weatherAPI)
            checks["ownedKeychainRoundTrip"] = keys.contains(.weatherAPI) && restoredKey == "owned-weather-fixture"
            try keys.save(nil, for: .weatherAPI)
            checks["ownedKeychainEntryDeleted"] = !keys.contains(.weatherAPI)
            service.select(.init(name: "İstanbul", latitude: 41.0082, longitude: 28.9784))
            service.setEnabled(true)
            checks["selectedAnonymousSourceActuallyFetched"] = await wait { service.snapshot?.source == .visualCrossing || service.error != nil } && service.snapshot?.source == .visualCrossing
            checks["liveCurrentHourlyAndDailyDecoded"] = service.snapshot?.current.temperature != nil && service.snapshot?.hourly.isEmpty == false && service.snapshot?.forecast.isEmpty == false
            host(WeatherDetail(service: service).padding(PocketSpacing.m).buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 368, height: 590))
            window.makeKeyAndOrderFront(nil)
            try await capture(window, at: directory.appendingPathComponent("popover.png"))
            checks["auditWindowIsActive"] = NSApp.isActive && window.isKeyWindow
            checks["popoverUsesProductionWidth"] = abs(window.contentLayoutRect.width - 368) < 1
            if let hour = service.snapshot?.hourly.first(where: { $0.time >= Date().timeIntervalSince1970 }) {
                let id = "weather.hour." + String(hour.id)
                let originalX = WeatherUIProbe.targets[id]?.frame.minX
                let next = await press(String(localized: "Sonraki Saatler"), in: window)
                try await Task.sleep(for: .milliseconds(250))
                checks["hourlyNextActuallyScrolls"] = next && originalX != nil && (WeatherUIProbe.targets[id]?.frame.minX ?? .infinity) < originalX! - 20
                let previous = await press(String(localized: "Önceki Saatler"), in: window)
                try await Task.sleep(for: .milliseconds(250))
                checks["hourlyPreviousRestoresFirstHours"] = previous && originalX != nil && abs((WeatherUIProbe.targets[id]?.frame.minX ?? .infinity) - originalX!) < 2
                checks["hourCardClickOpensActualDetails"] = await WeatherUIProbe.click(id, in: window) && WeatherUIProbe.contains("weather.hour-detail")
                try await capture(window, at: directory.appendingPathComponent("hour-details.png"))
                checks["hourDetailsCanBeClosed"] = await press(String(localized: "Saat Ayrıntısını Kapat"), in: window) && !WeatherUIProbe.contains("weather.hour-detail")
            } else { checks["hourlyNextActuallyScrolls"] = false }
            checks["nativeWeatherSettingsOpens"] = await press(String(localized: "Hava Durumu Ayarları"), in: window) && WeatherUIProbe.contains("weather.source-picker")
            try await Task.sleep(for: .milliseconds(200))
            checks["sourcePickerAndBasketPresent"] = WeatherUIProbe.contains("weather.source-picker") && WeatherUIProbe.contains("weather.basket")
            try await capture(window, at: directory.appendingPathComponent("settings.png"))
            checks["nativeWeatherSettingsReturnsToForecast"] = await press(String(localized: "Hava Durumuna Dön"), in: window) && WeatherUIProbe.contains("weather.current")
            host(ScrollView { WeatherSourcesView(service: service).padding(PocketSpacing.xl) }.buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 640, height: 680))
            try await Task.sleep(for: .milliseconds(300))
            checks["nativeCheckboxRemovesSource"] = await press("MET Norway", in: window) && !service.basket.sources.contains(.metNorway)
            checks["nativeCheckboxAddsSource"] = await press("MET Norway", in: window) && service.basket.sources.contains(.metNorway)
            checks["nativeAccountDisclosureOpens"] = await press(String(localized: "Ücretsiz hesapla kullanılan kaynaklar"), in: window) && WeatherUIProbe.contains("weather.source.weatherAPI")
            checks["nativeModelDisclosureOpens"] = await press(String(localized: "Open-Meteo modelleri"), in: window) && WeatherUIProbe.contains("weather.source.gfs")
            try await Task.sleep(for: .milliseconds(200))
            checks["nativeModelCheckboxAddsGFS"] = await press(WeatherSource.gfs.localizedTitle, in: window) && service.basket.sources.contains(.gfs)
            service.include(.weatherAPI, included: true)
            try await capture(window, at: directory.appendingPathComponent("basket.png"))
            let restored = WeatherService(defaults: preferences, credentials: keys)
            checks["basketSurvivesReload"] = restored.basket == service.basket && restored.location == service.location
            service.selectSource(.weatherAPI)
            checks["missingKeyDoesNotShowOtherSourceData"] = service.snapshot == nil && service.error != nil && !service.loading
            host(WeatherDetail(service: service).padding(PocketSpacing.m).buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 368, height: 590))
            try await capture(window, at: directory.appendingPathComponent("missing-key.png"))
            checks["missingKeyKeepsProductionWidth"] = abs(window.contentLayoutRect.width - 368) < 1
            checks["missingKeyActionOpensSettings"] = await press(String(localized: "API Anahtarı Ekle"), in: window) && WeatherUIProbe.contains("weather.source-picker")
            try await Task.sleep(for: .milliseconds(200))
            checks["keyEntryGroupOpensAutomatically"] = WeatherUIProbe.contains("weather.key.weatherAPI")
            try await capture(window, at: directory.appendingPathComponent("key-settings.png"))
            let nodes = ToolUIAudit.accessibilityNodes(window)
            if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) { try data.write(to: directory.appendingPathComponent("accessibility.json")) }
            for state in ["no-location", "loading", "unavailable", "current-only"] {
                let suite = namespace + "." + state
                let defaults = UserDefaults(suiteName: suite)!
                let fixture = WeatherService(defaults: defaults, credentials: keys, client: { _, location, _, _ in
                    if state == "loading" { try await Task.sleep(for: .seconds(60)) }
                    if state == "unavailable" { throw WeatherSourceError.unavailable }
                    return try WeatherProviderClient.decode([Data(#"{"currentConditions":{"temp":10}}"#.utf8)], source: .visualCrossing, location: location)
                })
                defer { fixture.setEnabled(false); defaults.removePersistentDomain(forName: suite) }
                if state != "no-location" {
                    fixture.select(.init(name: "İstanbul", latitude: 41.0082, longitude: 28.9784)); fixture.setEnabled(true)
                    if state != "loading" { _ = await wait { !fixture.loading } }
                }
                host(WeatherDetail(service: fixture).padding(PocketSpacing.m).buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 368, height: 590))
                try await capture(window, at: directory.appendingPathComponent(state + ".png"))
                switch state {
                case "no-location":
                    checks["emptyLocationHasNextAction"] = WeatherUIProbe.contains("weather.choose-location")
                    checks["emptyLocationActionOpensSettings"] = await press(String(localized: "Konum Seç"), in: window) && WeatherUIProbe.contains("weather.source-picker")
                case "loading": checks["loadingStateVisible"] = WeatherUIProbe.contains("weather.loading") && fixture.loading
                case "unavailable": checks["failedSourceHasRecoveryAction"] = WeatherUIProbe.contains("weather.unavailable") && fixture.snapshot == nil
                default: checks["missingForecastNotInvented"] = WeatherUIProbe.contains("weather.current-only") && fixture.snapshot?.hourly.isEmpty == true
                }
            }
        } catch { failure = error.localizedDescription }
        let report: [String: Any] = ["passed": failure == nil && !checks.isEmpty && checks.values.allSatisfy { $0 }, "checks":checks,
            "error":failure ?? "", "language":Bundle.main.preferredLocalizations.first ?? "unknown", "userSettingsChanged":false,
            "realProviderCredentialReads":false, "paidEndpointsCalled":false, "controlledWeatherStates":true,
            "inputMode":"AX-when-available-or-local-window-events", "accessibilityTrusted":AXIsProcessTrusted()]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: directory.appendingPathComponent("report.json")) }
    }
}
#endif
