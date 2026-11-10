#if DEBUG
import AppKit
import ApplicationServices
import ObjectiveC
import MacPocketAIUsage
import MacPocketCore
import ScreenCaptureKit
import SwiftUI
import UsageCore

/// Native fixture acceptance, isolated by bundle ID. No real accounts, CLI login or notifications.
@MainActor
enum AIUsageRuntimeAudit {
    static func prepareIfRequested() {
        guard AIUsageFixtures.requested else { return }
        for module in PocketModule.allCases { UserDefaults.standard.set(false, forKey: module.availabilityKey) }
        OnboardingRecord.markCompleted()
        UserDefaults.standard.set(false, forKey: PocketPreferenceKey.showWindowAtLaunch)
        var bar = MenuBarPreferences(); bar.enabled = [.aiUsage]; bar.visible = true; bar.layout = .separate
        bar.save(to: .standard)
    }

    static func run(destination: URL) async {
        guard AIUsageFixtures.requested else { return }
        let accessibility = AXUIElementSetAttributeValue(AXUIElementCreateApplication(getpid()), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let profileHome = AIUsageFixtures.profileSearchHome
        defer { try? FileManager.default.removeItem(at: profileHome) }
        for name in [".claude", ".claude-work"] {
            let folder = profileHome.appending(path: name)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data().write(to: folder.appending(path: "settings.json"))
        }
        try? await Task.sleep(for: .seconds(1))
        let service = AIUsageService.shared
        var checks: [String: Bool] = [:], rows: [[String: Any]] = []
        func record(_ name: String, _ condition: Bool) { checks[name] = condition }
        let status = PocketApplicationState.shared.statusItem
        record("fourIndependentAccounts", service.boards.count == 4)
        record("twoClaudeAccounts", service.enabledAccounts.filter { $0.provider == .claude }.count == 2)
        record("remainingValues", service.menuBarReading.lines[0].contains("18%") && service.menuBarReading.lines[0].contains("75%"))
        record("nativeStatusImage", (status.aiUsageDiagnosticImage?.size.width ?? 0) > 20)
        record("nativeProviderLogoImage", status.aiUsageDiagnosticImage?.isTemplate == false)
        record("claudeLogoPackaged", Bundle.main.url(forResource: "AIProviderClaude", withExtension: "png") != nil)
        record("codexLogoPackaged", Bundle.main.url(forResource: "AIProviderOpenAI", withExtension: "png") != nil)
        let prefix = destination.deletingPathExtension().path
        if let tiff = status.aiUsageDiagnosticImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: prefix + "-menubar.png"))
        }
        if let popover = status.showAIUsageForDiagnostics() {
            try? await Task.sleep(for: .milliseconds(700))
            record("popoverScreenshot", await snapshot(popover, to: URL(fileURLWithPath: prefix + "-popover.png")))
            let nodes = nodes(popover)
            record("popoverHasBothClaudeNames", nodes.contains("Personal") && nodes.contains("Work"))
            rows.append(["surface": "nativePopover", "width": popover.frame.width, "height": popover.frame.height, "nodes": nodes])
        } else { record("popoverShown", false) }
        status.closeDiagnosticPopover()
        record("settingsSceneActionCaptured", AIUsageIntegration.shared.openSettingsWindow != nil)
        AIUsageIntegration.shared.openSettingsWindow?()
        try? await Task.sleep(for: .milliseconds(500))
        let actualSettings = NSApp.windows.first { $0.isVisible && $0.title == String(localized: "AI Kotaları") }
        record("actualSwiftUISettingsSceneOpens", actualSettings != nil)
        actualSettings?.performClose(nil)
        for width in [620, 800] {
            let window = makeWindow(AIUsageSettingsView(service: service), size: NSSize(width: width, height: 720))
            try? await Task.sleep(for: .milliseconds(500))
            let content = nodes(window)
            record("settings\(width)AccountRows", content.contains("Personal") && content.contains("Work"))
            record("settings\(width)Screenshot", await snapshot(window, to: URL(fileURLWithPath: prefix + "-settings-\(width).png")))
            rows.append(["surface": "overview", "width": width, "nodes": content])
            _ = press(String(localized: "Hesaplar"), in: window)
            try? await Task.sleep(for: .milliseconds(200))
            record("accountsTab\(width)", nodes(window).contains(String(localized: "Oturum Kaynağı")))
            record("accountsScreenshot\(width)", await snapshot(window, to: URL(fileURLWithPath: prefix + "-accounts-\(width).png")))
            _ = press(String(localized: "Ayarlar"), in: window)
            try? await Task.sleep(for: .milliseconds(200))
            record("settingsTab\(width)", nodes(window).contains(String(localized: "Kota yenileme aralığı")))
            record("optionsScreenshot\(width)", await snapshot(window, to: URL(fileURLWithPath: prefix + "-options-\(width).png")))
            window.orderOut(nil)
        }
        let originalSettings = service.settings, originalBoards = service.boards
        var emptySettings = originalSettings; emptySettings.accounts = []; service.setSettings(emptySettings)
        let emptyWindow = makeWindow(AIUsageSettingsView(service: service), size: NSSize(width: 620, height: 560))
        try? await Task.sleep(for: .milliseconds(250))
        record("emptyAccountAction", nodes(emptyWindow).contains(String(localized: "İlk Hesabı Ekle")))
        record("emptyScreenshot", await snapshot(emptyWindow, to: URL(fileURLWithPath: prefix + "-empty.png")))
        emptyWindow.orderOut(nil)
        service.setSettings(originalSettings); service.setFixtureBoards(originalBoards)
        let add = makeWindow(AIUsageSettingsView(service: service, initiallyAdding: true), size: NSSize(width: 680, height: 720))
        try? await Task.sleep(for: .milliseconds(700))
        let sheet = add.attachedSheet
        record("addAccountNativeSheet", sheet != nil)
        if let sheet {
            let content = nodes(sheet)
            record("addAccountSeparateClaudeOption", content.contains(String(localized: "Yeni hesaba giriş yap")))
            record("claudeFolderSearchAction", content.contains(String(localized: "Claude Klasörlerini Bul")))
            record("claudeProfileFolderDiscovered", content.contains(where: { $0.contains(".claude-work") }))
            record("claudeDefaultSessionWithoutFolder", content.contains(where: { $0.contains(String(localized: "Varsayılan Claude Code oturumu")) }))
            // Discovery and SwiftUI's accessibility children become ready asynchronously.
            // The path field's placeholder also contains '.claude-work'; it isn't readiness evidence.
            var selectedProfile = false
            for _ in 0..<10 {
                if press(".claude-work", in: sheet) { selectedProfile = true; break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            record("claudeFoundProfileSelectable", selectedProfile)
            try? await Task.sleep(for: .milliseconds(200))
            record("claudeSelectionFillsPath", nodes(sheet).contains(profileHome.appending(path: ".claude-work").path))
            record("claudeFolderRescan", press(String(localized: "Claude Klasörlerini Bul"), in: sheet))
            try? await Task.sleep(for: .milliseconds(300))
            record("claudeRescanKeepsSelection", nodes(sheet).contains(profileHome.appending(path: ".claude-work").path))
            record("addAccountScreenshot", await snapshot(sheet, to: URL(fileURLWithPath: prefix + "-add-account.png")))
            rows.append(["surface": "addSheet", "nodes": content])
            add.endSheet(sheet)
        }
        add.orderOut(nil)
        var settings = service.settings; settings.mode = .used; service.setSettings(settings)
        record("switchUsedMode", service.menuBarReading.lines[0].contains("82%") && service.menuBarReading.lines[0].contains("25%"))
        settings.mode = .remaining; settings.floatingPanel = true; service.setSettings(settings)
        AIUsageIntegration.shared.configure(preferences: MenuBarSettingsStore.shared.preferences)
        try? await Task.sleep(for: .milliseconds(500))
        if let panel = NSApp.windows.first(where: { $0.isVisible && $0 is NSPanel && $0.title == String(localized: "AI Kotaları") }) {
            record("verticalStripNarrow", panel.frame.width <= 110)
            record("verticalFloatingScreenshot", await snapshot(panel, to: URL(fileURLWithPath: prefix + "-floating-vertical.png")))
            settings.floatingHorizontal = true; service.setSettings(settings)
            AIUsageIntegration.shared.configure(preferences: MenuBarSettingsStore.shared.preferences)
            try? await Task.sleep(for: .milliseconds(500))
            record("horizontalFloatingLayout", panel.frame.width > panel.frame.height)
            record("horizontalStripCompact", panel.frame.height <= 110)
            record("horizontalFloatingScreenshot", await snapshot(panel, to: URL(fileURLWithPath: prefix + "-floating-horizontal.png")))
        } else { record("floatingPanelVisible", false) }
        settings.floatingPanel = false; service.setSettings(settings)
        var bar = MenuBarSettingsStore.shared.preferences; bar.enabled = []; MenuBarSettingsStore.shared.preferences = bar
        AIUsageIntegration.shared.configure(preferences: bar)
        record("disableStopsPolling", !service.active && service.refreshing.isEmpty)
        // Direct quota surfaces exercise real layout without credentials or accessibility automation.
        var longAccount = originalSettings.accounts[0]
        longAccount.name = "Design & Engineering · International Production Account"
        let session = UsageLimit(id: "session", label: "Session", percentUsed: 98, resetsAt: .now.addingTimeInterval(3_600), severity: .critical)
        let weekly = UsageLimit(id: "weekly_all", label: "Weekly", percentUsed: 45, resetsAt: .now.addingTimeInterval(172_800), severity: .normal)
        let scoped = UsageLimit(id: "weekly_scoped#Claude Sonnet · Extended model context", label: "Scoped", percentUsed: 75, resetsAt: nil, severity: .warning)
        for scenario in ["critical", "exhausted-used", "stale", "sign-in", "loading", "long-model"] {
            var settings = originalSettings
            if scenario == "exhausted-used" { settings.mode = .used }
            let limits: [UsageLimit] = scenario == "sign-in" ? [] : scenario == "long-model" ? [session, weekly, scoped] :
                scenario == "exhausted-used" ? [UsageLimit(id: "session", label: "Session", percentUsed: 100, resetsAt: .now.addingTimeInterval(-60), severity: .critical)] : [session, weekly]
            let fetchStatus: FetchStatus = scenario == "stale" ? .stale(reason: "network") : scenario == "sign-in" ? .needsSignIn : .ok
            let snapshot: UsageSnapshot? = scenario == "loading" ? nil : .init(provider: .claude, fetchedAt: .now.addingTimeInterval(-900), limits: limits, status: fetchStatus)
            let surface = VStack(alignment: .leading, spacing: 14) {
                Text(settings.mode.localizedTitle).font(.caption).foregroundStyle(.secondary)
                AIUsageAccountQuotaView(account: longAccount, snapshot: snapshot, settings: settings, refreshing: scenario == "loading", dense: true)
                Spacer(minLength: 0)
            }.padding(16).frame(width: 320, height: 360, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor))
            let window = makeWindow(surface, size: NSSize(width: 320, height: 360))
            try? await Task.sleep(for: .milliseconds(150))
            record("quotaState-\(scenario)", await self.snapshot(window, to: URL(fileURLWithPath: prefix + "-quota-\(scenario).png")))
            window.orderOut(nil)
        }
        let report: [String: Any] = ["checks": checks, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "rows": rows,
            "language": Bundle.main.preferredLocalizations.first ?? "unknown", "realCredentialReads": false,
            "realQuotaRequests": false, "realCLILogins": false, "selfAccessibilityEnableResult": accessibility.rawValue]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination, options: .atomic)
        }
    }

    private static func makeWindow<Content: View>(_ content: Content, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "AI Kotaları")
        window.contentView = NSHostingView(rootView: content.pocketAppearanceRoot(rebuildsOnTokenChange: false))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        return window
    }
    private static func press(_ label: String, in root: NSObject) -> Bool {
        var pending = [root], seen = Set<ObjectIdentifier>()
        while let node = pending.popLast(), seen.count < 3_000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            let names = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { key -> String? in
                let selector = NSSelectorFromString(key)
                return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
            }
            let action = NSSelectorFromString("accessibilityPerformPress")
            if names.contains(where: { $0.contains(label) }), node.responds(to: action),
               let method = class_getInstanceMethod(type(of: node), action) {
                typealias Press = @convention(c) (AnyObject, Selector) -> ObjCBool
                let invoke = unsafeBitCast(method_getImplementation(method), to: Press.self)
                if invoke(node, action).boolValue { return true }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        return false
    }
    private static func nodes(_ root: NSObject) -> [String] {
        var pending = [root], seen = Set<ObjectIdentifier>(), values: [String] = []
        while let node = pending.popLast(), seen.count < 3_000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
                let selector = NSSelectorFromString(key)
                if node.responds(to: selector), let value = node.perform(selector)?.takeUnretainedValue() as? String, !value.isEmpty {
                    values.append(value)
                }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        return values
    }
    private static func snapshot(_ window: NSWindow, to url: URL) async -> Bool {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let target = content.windows.first(where: { Int($0.windowID) == window.windowNumber }) else { return false }
            let config = SCStreamConfiguration(); config.width = Int(target.frame.width * window.backingScaleFactor)
            config.height = Int(target.frame.height * window.backingScaleFactor); config.showsCursor = false; config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
            try data.write(to: url, options: .atomic); return true
        } catch { return false }
    }
}
#endif
