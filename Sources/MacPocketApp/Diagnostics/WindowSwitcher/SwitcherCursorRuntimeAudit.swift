#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor enum SwitcherCursorRuntimeAudit {
    static func run(destination: URL,checks: inout [String: Bool]) async -> [[String: Any]] {
        let suite = "MacPocket.CursorSettingsAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { checks["cursorSettingsDefaultsExist"] = false;return [] }
        defer { defaults.removePersistentDomain(forName: suite) }
        var evidence: [[String: Any]] = []
        for width in [520.0,760.0] {
            defaults.set(SwitcherCursorPolicy.never.rawValue,forKey: SwitcherCursorPolicy.key)
            let window = NSWindow(contentRect: NSRect(x: 120,y: 180,width: width,height: 360),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: Form { SwitcherCursorSettings(defaults: defaults) }.formStyle(.grouped)
                .environment(\.locale,pocketLocale).preferredColorScheme(.light).background(Color(nsColor: .windowBackgroundColor)))
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(120))
            let prefix = "cursor-settings-\(Int(width))"
            let nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix + "ThreeNativeRadioChoices"] = nodes.filter { $0["role"] == "AXRadioButton" }.count == 3
            for policy in [SwitcherCursorPolicy.always,.differentDisplay,.never] {
                let pressed = SwitcherAppearanceRuntimeAudit.press(policy.localizedTitle,in: window,role: .radioButton)
                let changed = await wait { SwitcherCursorPolicy.load(defaults) == policy }
                checks[prefix + "NativeChoice-" + policy.rawValue] = pressed && changed
            }
            _ = SwitcherAppearanceRuntimeAudit.press(SwitcherCursorPolicy.differentDisplay.localizedTitle,in: window,role: .radioButton)
            try? await Task.sleep(for: .milliseconds(100))
            checks[prefix + "NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let w = Double(node["width"] ?? ""),w > 0 else { return false }
                return x < window.frame.minX - 2 || x + w > window.frame.maxX + 2
            }
            checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + ".png"))
            evidence.append(["width": width,"nodes": nodes])
            window.orderOut(nil)
        }
        // The production controller must preserve the session policy across dismissal and pass
        // it to focus; the model's now-changed defaults must not silently replace that policy.
        let previous = UserDefaults.standard.object(forKey: SwitcherCursorPolicy.key)
        defer { if let previous { UserDefaults.standard.set(previous,forKey: SwitcherCursorPolicy.key) } else { UserDefaults.standard.removeObject(forKey: SwitcherCursorPolicy.key) } }
        UserDefaults.standard.set(SwitcherCursorPolicy.always.rawValue,forKey: SwitcherCursorPolicy.key)
        let row = SwitchableWindow(id: "cursor-fixture",processID: 1,application: "Fixture",title: "Cursor",applicationURL: nil,
            minimized: false,hidden: false,fullScreen: false,frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,
            canFullScreen: false,launchedAt: nil,lastFocusedAt: nil,windowID: 1)
        let follower = CursorAuditFollower(),model = WindowSwitcherModel(windows: [row],catalog: CursorAuditCatalog(),cursorFollower: follower,permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: model,foregroundApplication: { NSRunningApplication.current })
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.presentation.style = .titles
        shortcut.releaseBehavior = .hold
        model.selection = row.id
        _ = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut)
        checks["cursorPolicyCapturedOnSessionStart"] = controller.activeCursorPolicy == .always
        UserDefaults.standard.set(SwitcherCursorPolicy.never.rawValue,forKey: SwitcherCursorPolicy.key)
        controller.commitForAudit()
        checks["cursorCommitUsesCapturedPolicyAfterDismissal"] = await wait { follower.policies == [.always] }
        _ = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut)
        checks["cursorNextSessionReadsChangedPolicy"] = controller.activeCursorPolicy == .never
        controller.stopForModule()
        checks["cursorStopClearsPolicyAndInputResources"] = controller.activeCursorPolicy == nil && controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        return evidence
    }
    private static func wait(_ condition: @MainActor () -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < end { if condition() { return true };try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }
}
@MainActor private final class CursorAuditFollower: WindowCursorFollowing {
    var policies: [SwitcherCursorPolicy] = []
    func captureOrigin() -> WindowCursorOrigin? { .init(point: CGPoint(x: 20,y: 20)) }
    func follow(_ target: WindowFocusDestination,from origin: WindowCursorOrigin,policy: SwitcherCursorPolicy) -> WindowCursorFollowOutcome { policies.append(policy);return .moved }
}
private actor CursorAuditCatalog: WindowCatalogServing {
    func snapshot() async -> WindowCatalogReport { .init(windows: [],accessibilityGranted: true,partial: false) }
    func focus(_ id: String) async throws {}
    func focusDestination(_ id: String) async -> WindowFocusDestination? { .init(processID: 1,launchedAt: Date(),windowID: 1,frame: CGRect(x: 100,y: 100,width: 200,height: 200)) }
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}
#endif
