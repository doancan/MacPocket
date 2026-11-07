#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

/// Own native HUD/settings with a fake badge provider. Actual Dock transport is accepted separately.
@MainActor enum SwitcherBadgeRuntimeAudit {
    static func run(destination: URL,checks: inout [String: Bool]) async -> [[String: Any]] {
        let suite = "MacPocket.BadgeAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { checks["badgeDefaultsExist"] = false;return [] }
        defer { defaults.removePersistentDomain(forName: suite) }
        var evidence: [[String: Any]] = []
        for width in [520.0,760.0] {
            let window = NSWindow(contentRect: NSRect(x: 100,y: 200,width: width,height: 260),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: Form { SwitcherBadgeSettings(defaults: defaults) }.formStyle(.grouped).environment(\.locale,pocketLocale))
            window.makeKeyAndOrderFront(nil);await settle()
            let prefix = "badge-settings-\(Int(width))",label = String(localized: "Dock bildirim rozetleri")
            for enabled in [false,true] {
                let pressed = SwitcherAppearanceRuntimeAudit.press(label,in: window)
                let saved = await wait { SwitcherPresentation.load(defaults).showBadges == enabled }
                checks[prefix + "Toggle-\(enabled)"] = pressed && saved
            }
            await settle()
            let nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix + "NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let width = Double(node["width"] ?? ""),width > 0 else { return false }
                return x < window.frame.minX - 2 || x+width > window.frame.maxX+2
            }
            checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + ".png"))
            evidence.append(["width": width,"nodes": nodes]);window.orderOut(nil)
        }
        let global = UserDefaults.standard,previous = global.object(forKey: "switcher.showBadges")
        defer { if let previous { global.set(previous,forKey: "switcher.showBadges") } else { global.removeObject(forKey: "switcher.showBadges") } }
        let rows: [SwitchableWindow] = (0..<5).map { index in
            let owner = max(0,index-1)
            return .init(id: "badge-\(index)",processID: Int32(9000+owner),application: "Fixture \(owner)",title: "Window \(index)",
                applicationURL: URL(fileURLWithPath: "/Applications/Fixture\(owner).app"),minimized: index == 1,hidden: false,fullScreen: false,frontmost: false,
                windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,launchedAt: Date(timeIntervalSince1970: 1),lastFocusedAt: nil,windowID: UInt32(index+1))
        }
        let text = "Very long Dock label 👨‍👩‍👧‍👦",labels = ["12","!",text,"0"]
        let values = Dictionary(uniqueKeysWithValues: rows.dropFirst().enumerated().compactMap { index,row -> (DockBadgeTarget,DockApplicationBadge)? in
            guard let target = DockBadgeTarget(row),let badge = DockApplicationBadge(labels[index]) else { return nil };return (target,badge)
        })
        for style in SwitcherStyle.allCases {
            for dark in [false,true] {
                let provider = BadgeAuditReader(values)
                let model = WindowSwitcherModel(windows: rows,badgeReader: provider,permitsCapture: { false })
                let controller = WindowSwitcherHotkeyController(model: model)
                var shortcut = SwitcherShortcut.defaultOptionTab
                shortcut.presentation.style = style;shortcut.presentation.autoSize = false;shortcut.presentation.sizeScale = 0.6
                shortcut.presentation.theme = dark ? .dark : .light;shortcut.presentation.showBadges = true;shortcut.presentation.showSpaces = true
                shortcut.presentation.animateOpening = false;shortcut.presentation.animateClosing = false
                let prefix = "badge-\(style.rawValue)-\(dark ? "dark" : "light")"
                global.set(true,forKey: "switcher.showBadges")
                if let panel = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut) {
                    checks[prefix + "ApplicationValuesArrive"] = await wait { model.applicationBadges.count == 4 }
                    await settle()
                    checks[prefix + "SameApplicationWindowsShareBadge"] = model.applicationBadge(for: rows[0])?.label == "12" && model.applicationBadge(for: rows[1])?.label == "12"
                    let values = WindowSwitcherRuntimeAudit.accessibilityValues(panel)
                    checks[prefix + "AccessibleFullLongLabel"] = values.contains { $0.contains(DockApplicationBadge(text)!.localizedDescription) }
                    checks[prefix + "AccessibleNumericAndTextLabels"] = ["12","!","0"].allSatisfy { label in values.contains { $0.contains(DockApplicationBadge(label)!.localizedDescription) } }
                    checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(panel,to: destination.appendingPathComponent(prefix + ".png"))
                    global.set(false,forKey: "switcher.showBadges")
                    checks[prefix + "CapturedPresetKeepsBadgeChoice"] = controller.presentation.showBadges
                    await provider.set([:])
                    checks[prefix + "EmptySnapshotClearsLabels"] = await wait { model.applicationBadges.isEmpty }
                } else { checks[prefix + "PanelExists"] = false }
                controller.stopForModule()
                checks[prefix + "StopClearsCacheAndWorker"] = model.applicationBadges.isEmpty && controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
                // A per-preset false override must prevent reads even while the global setting is true.
                global.set(true,forKey: "switcher.showBadges");shortcut.presentation.showBadges = false
                _ = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut)
                let before = await provider.requests;await settle()
                let after = await provider.requests
                checks[prefix + "DisabledPresetDoesNotReadDock"] = before == after && model.applicationBadges.isEmpty && !controller.presentation.showBadges
                controller.stopForModule()
                evidence.append(["style": style.rawValue,"dark": dark,"minimumScale": 0.6,"provider": "fake-owned-application-badges","requests": after])
            }
        }
        return evidence
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(140)) }
    private static func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < end { if await condition() { return true };try? await Task.sleep(for: .milliseconds(20)) }
        return false
    }
}
private actor BadgeAuditReader: DockApplicationBadgeReading {
    var values: [DockBadgeTarget:DockApplicationBadge]
    private(set) var requests = 0
    init(_ values: [DockBadgeTarget:DockApplicationBadge]) { self.values = values }
    func set(_ values: [DockBadgeTarget:DockApplicationBadge]) { self.values = values }
    func badges(for targets: [DockBadgeTarget]) async -> [DockBadgeTarget:DockApplicationBadge] {
        requests += 1;let allowed = Set(targets);return values.filter { allowed.contains($0.key) }
    }
}
#endif
