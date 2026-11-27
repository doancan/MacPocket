#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor enum SwitcherExceptionsRuntimeAudit {
    static func run(destination: URL, checks: inout [String: Bool]) async -> [[String: Any]] {
        let name = "com.doancan.MacPocket.SwitcherExceptionsAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { checks["exceptionsIsolatedDefaults"] = false; return [] }
        let oldAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { defaults.removePersistentDomain(forName: name); NSApp.appearance = oldAppearance }
        let rule = SwitcherExceptionRule(target: .bundleIdentifier, value: "com.example.Editor", visibility: .titleContains,
                                         titlePatterns: ["Private", "[Draft]", "İş"], shortcuts: .fullscreen)
        var evidence: [[String: Any]] = []
        for width in [560.0, 760.0] {
            _ = SwitcherExceptionStore.save([rule], defaults)
            let window = NSWindow(contentRect: NSRect(x: 100,y: 180,width: width,height: 540),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: SwitcherExceptionsEditor(defaults: defaults).padding(20).background(Color(nsColor: .windowBackgroundColor)).environment(\.locale,pocketLocale).preferredColorScheme(.light))
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(160))
            let prefix = "exceptions-\(Int(width))"
            var nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix + "ContainsEditAndEnableControls"] = nodes.filter { ["AXCheckBox","AXButton"].contains($0["role"] ?? "") }.count >= 4
            checks[prefix + "NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let w = Double(node["width"] ?? ""),w > 0 else { return false }
                return x < window.frame.minX - 2 || x + w > window.frame.maxX + 2
            }
            checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + ".png"))
            if WindowPreviewProvider.permitted {
                checks[prefix + "RealScreenCapture"] = await capture(window,to: destination.appendingPathComponent(prefix + "-screen.png"))
            }
            let disabled = SwitcherAppearanceRuntimeAudit.press(rule.value, in: window)
            try? await Task.sleep(for: .milliseconds(100))
            checks[prefix + "NativeCheckboxPersistsDisabledRule"] = disabled && SwitcherExceptionStore.load(defaults).rules.first?.enabled == false
            _ = SwitcherAppearanceRuntimeAudit.press(rule.value,in: window)
            try? await Task.sleep(for: .milliseconds(70))
            checks[prefix + "NativeCheckboxRestoresRule"] = SwitcherExceptionStore.load(defaults).rules.first?.enabled == true
            let editLabel = String(localized: "\(rule.value) kuralını düzenle")
            _ = SwitcherAppearanceRuntimeAudit.press(editLabel,in: window,role: .button)
            try? await Task.sleep(for: .milliseconds(150))
            checks[prefix + "EditOpensSheet"] = !window.sheets.isEmpty
            if let sheet = window.sheets.first {
                nodes = ToolUIAudit.accessibilityNodes(sheet)
                checks[prefix + "RuleFormContainsNativePickersAndTextFields"] = nodes.filter { $0["role"] == "AXPopUpButton" }.count >= 3
                    && nodes.contains { $0["role"] == "AXTextField" || $0["role"] == "AXTextArea" }
                checks[prefix + "RuleFormNoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                    guard let x = Double(node["x"] ?? ""),let w = Double(node["width"] ?? ""),w > 0 else { return false }
                    return x < sheet.frame.minX - 2 || x + w > sheet.frame.maxX + 2
                }
                checks[prefix + "RuleFormSnapshot"] = WindowSwitcherRuntimeAudit.snapshot(sheet,to: destination.appendingPathComponent(prefix + "-form.png"))
                if WindowPreviewProvider.permitted {
                    checks[prefix + "RealFormScreenCapture"] = await capture(sheet,to: destination.appendingPathComponent(prefix + "-form-screen.png"))
                }
                let before = defaults.data(forKey: SwitcherExceptionStore.key)
                _ = SwitcherAppearanceRuntimeAudit.press(String(localized: "Vazgeç"),in: sheet,role: .button)
                let closed = await wait { window.sheets.isEmpty }
                checks[prefix + "CancelClosesSheetWithoutChangingPreferences"] = closed && defaults.data(forKey: SwitcherExceptionStore.key) == before
            }
            _ = SwitcherAppearanceRuntimeAudit.press(String(localized: "İstisna Ekle"),in: window,role: .button)
            try? await Task.sleep(for: .milliseconds(150))
            if let sheet = window.sheets.first {
                _ = SwitcherAppearanceRuntimeAudit.press(String(localized: "İstisnayı Kaydet"),in: sheet,role: .button)
                try? await Task.sleep(for: .milliseconds(80))
                let text = WindowSwitcherRuntimeAudit.accessibilityValues(sheet).joined(separator: " ")
                checks[prefix + "EmptyTargetShowsValidationAndKeepsSheetOpen"] = !window.sheets.isEmpty
                    && text.contains(String(localized: "Bir uygulama yolu veya bundle kimliği gir.")) && SwitcherExceptionStore.load(defaults).rules.count == 1
                _ = SwitcherAppearanceRuntimeAudit.press(String(localized: "Vazgeç"),in: sheet,role: .button)
                _ = await wait { window.sheets.isEmpty }
            } else { checks[prefix + "AddOpensSheet"] = false }
            // Saving a populated production form goes through its native default button.
            // A fresh host avoids replacing a parent content view while its previous sheet's
            // native dismissal transaction is still finishing. This is an audit fixture lifetime.
            var saves = 0
            let saveWindow = NSWindow(contentRect: NSRect(x: 100,y: 180,width: width,height: 680),
                                      styleMask: [.titled,.closable],backing: .buffered,defer: false)
            saveWindow.isReleasedWhenClosed = false
            saveWindow.appearance = NSAppearance(named: .aqua)
            saveWindow.contentView = NSHostingView(rootView: SwitcherExceptionRuleForm(rule: rule) { edited in saves += 1;return SwitcherExceptionStore.save([edited],defaults) }.environment(\.locale,pocketLocale))
            saveWindow.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(100))
            let saved = SwitcherAppearanceRuntimeAudit.press(String(localized: "İstisnayı Kaydet"),in: saveWindow,role: .button)
            let committed = await wait { saves == 1 }
            checks[prefix + "NativeSaveCommitsValidRuleOnce"] = saved && committed && SwitcherExceptionStore.load(defaults).rules == [rule]
            saveWindow.orderOut(nil)
            evidence.append(["width": width,"nodes": nodes,"snapshot": prefix + ".png"])
            window.orderOut(nil)
        }
        return evidence
    }
    private static func wait(_ condition: @MainActor () -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    private static func capture(_ window: NSWindow, to url: URL) async -> Bool {
        guard window.windowNumber > 0, let launch = SwitcherForegroundApplication(NSRunningApplication.current).launchedAt else { return false }
        let target = SwitchableWindow(id: "owned-exception-editor",processID: getpid(),application: "MacPocket",title: "",
            applicationURL: Bundle.main.bundleURL,minimized: false,hidden: false,fullScreen: false,frontmost: true,
            windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,launchedAt: launch,lastFocusedAt: nil,
            windowID: UInt32(window.windowNumber))
        let provider = WindowPreviewProvider()
        for _ in 0..<3 {
            do {
                let image = try await provider.image(for: target,maxPixels: CGSize(width: 1440,height: 1600))
                guard let png = NSBitmapImageRep(cgImage: image.cgImage).representation(using: .png,properties: [:]) else { return false }
                try png.write(to: url,options: .atomic)
                return true
            } catch { try? await Task.sleep(for: .milliseconds(200)) }
        }
        return false
    }

}
#endif
