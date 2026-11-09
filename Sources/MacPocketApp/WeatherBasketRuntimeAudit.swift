#if DEBUG
import AppKit
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
    private static func press(_ label: String, in root: NSObject) -> Bool {
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
                if action(node, selector).boolValue { return true }
            }
            if let window = node as? NSWindow, let content = window.contentView { pending.append(content) }
            if let view = node as? NSView { pending += view.subviews }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        return false
    }
    private static func capture(_ window: NSWindow, at destination: URL) async throws {
        guard WindowPreviewProvider.permitted else { throw WindowPreviewError.permissionRequired }
        try await Task.sleep(for: .milliseconds(300))
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
        let controller = NSHostingController(rootView: content.frame(width: size.width, height: size.height, alignment: .topLeading))
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
    }
    private static func run(_ directory: URL) async {
        let namespace = "com.doancan.MacPocket.weather.audit." + UUID().uuidString
        let preferences = UserDefaults(suiteName: namespace)!, keys = WeatherKeychainStore(namespace: namespace)
        let service = WeatherService(defaults: preferences, credentials: keys)
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 368, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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
            host(WeatherDetail(service: service).padding(PocketSpacing.m).buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 368, height: 540))
            window.makeKeyAndOrderFront(nil)
            try await capture(window, at: directory.appendingPathComponent("popover.png"))
            checks["popoverUsesProductionWidth"] = abs(window.contentLayoutRect.width - 368) < 1
            checks["sourcePickerAndBasketPresent"] = ToolUIAudit.accessibilityNodes((window.contentView as NSObject?) ?? window).contains { ($0["name"] ?? "").contains(String(localized: "Kaynak Sepeti")) }
            host(ScrollView { WeatherSourcesView(service: service).padding(PocketSpacing.xl) }.buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 640, height: 680))
            try await Task.sleep(for: .milliseconds(300))
            checks["nativeCheckboxRemovesSource"] = press("MET Norway", in: window) && !service.basket.sources.contains(.metNorway)
            checks["nativeCheckboxAddsSource"] = press("MET Norway", in: window) && service.basket.sources.contains(.metNorway)
            checks["nativeModelDisclosureOpens"] = press(String(localized: "Open-Meteo modelleri"), in: window)
            try await Task.sleep(for: .milliseconds(200))
            checks["nativeModelCheckboxAddsGFS"] = press(WeatherSource.gfs.localizedTitle, in: window) && service.basket.sources.contains(.gfs)
            checks["nativeAccountDisclosureOpens"] = press(String(localized: "Ücretsiz hesapla kullanılan kaynaklar"), in: window)
            service.include(.weatherAPI, included: true)
            try await capture(window, at: directory.appendingPathComponent("basket.png"))
            let restored = WeatherService(defaults: preferences, credentials: keys)
            checks["basketSurvivesReload"] = restored.basket == service.basket && restored.location == service.location
            service.selectSource(.weatherAPI)
            checks["missingKeyDoesNotShowOtherSourceData"] = service.snapshot == nil && service.error != nil && !service.loading
            host(WeatherDetail(service: service).padding(PocketSpacing.m).buttonStyle(.pocketSecondary), in: window, size: NSSize(width: 368, height: 540))
            try await capture(window, at: directory.appendingPathComponent("missing-key.png"))
            checks["missingKeyKeepsProductionWidth"] = abs(window.contentLayoutRect.width - 368) < 1
            let nodes = ToolUIAudit.accessibilityNodes(window)
            if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) { try data.write(to: directory.appendingPathComponent("accessibility.json")) }
        } catch { failure = error.localizedDescription }
        let report: [String: Any] = ["passed": failure == nil && !checks.isEmpty && checks.values.allSatisfy { $0 }, "checks":checks,
            "error":failure ?? "", "language":Bundle.main.preferredLocalizations.first ?? "unknown", "userSettingsChanged":false,
            "realProviderCredentialReads":false, "paidEndpointsCalled":false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: directory.appendingPathComponent("report.json")) }
    }
}
#endif
