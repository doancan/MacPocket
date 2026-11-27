#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor enum SwitcherNavigationRuntimeAudit {
    static func run(destination: URL, checks: inout [String: Bool]) async throws -> [[String: Any]] {
        let defaults = UserDefaults.standard
        let keys = [SwitcherNavigationOptions.arrowsKey,SwitcherNavigationOptions.vimKey,SwitcherActionBindings.key]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0,defaults.object(forKey: $0)) })
        defer { for key in keys { if let value = saved[key] ?? nil { defaults.set(value,forKey: key) } else { defaults.removeObject(forKey: key) } } }
        let rows = windows(37)
        var evidence: [[String: Any]] = []
        for style in SwitcherStyle.allCases {
            defaults.set(true,forKey: SwitcherNavigationOptions.arrowsKey)
            defaults.set(true,forKey: SwitcherNavigationOptions.vimKey)
            let model = WindowSwitcherModel(windows: rows,permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model,foregroundApplication: { NSRunningApplication.current })
            var shortcut = SwitcherShortcut.defaultOptionTab
            shortcut.presentation.style = style
            shortcut.presentation.autoSize = false
            shortcut.releaseBehavior = .hold
            model.selection = rows[0].id
            guard let panel = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut) else { checks["navigation-\(style.rawValue)-Panel"] = false;continue }
            let prefix = "navigation-" + style.rawValue
            await WindowSwitcherRuntimeAudit.sendKey(37,to: panel,characters: "l")
            checks[prefix + "LNext"] = model.selection == rows[1].id && !model.isSearching
            await WindowSwitcherRuntimeAudit.sendKey(4,to: panel,characters: "h")
            checks[prefix + "HPrevious"] = model.selection == rows[0].id
            let columns = controller.layout.columns
            await WindowSwitcherRuntimeAudit.sendKey(125,to: panel)
            checks[prefix + "DownArrowNextRow"] = model.selection == rows[min(columns,rows.count-1)].id
            await WindowSwitcherRuntimeAudit.sendKey(126,to: panel)
            checks[prefix + "UpArrowPreviousRow"] = model.selection == rows[0].id
            await WindowSwitcherRuntimeAudit.sendKey(38,to: panel,characters: "j")
            checks[prefix + "JNextRow"] = model.selection == rows[min(columns,rows.count-1)].id
            await WindowSwitcherRuntimeAudit.sendKey(40,to: panel,characters: "k")
            checks[prefix + "KPreviousRow"] = model.selection == rows[0].id
            if columns > 1, rows.count % columns != 0 {
                let lastStart = (rows.count - 1) / columns * columns
                model.selection = rows[lastStart - 1].id
                await WindowSwitcherRuntimeAudit.sendKey(38,to: panel,characters: "j")
                checks[prefix + "IncompleteRowClampsToLastCard"] = model.selection == rows.last?.id
            }
            model.selection = rows[0].id
            await WindowSwitcherRuntimeAudit.sendKey(6,to: panel,characters: "h")
            checks[prefix + "LogicalCharacterOverridesPhysicalUSPosition"] = model.selection == rows.last?.id
            await WindowSwitcherRuntimeAudit.sendKey(44,to: panel,characters: "/")
            checks[prefix + "SlashBeginsEmptySearch"] = model.isSearching && model.sessionSearch.isEmpty
            for (code,text) in [(UInt16(4),"h"),(38,"j"),(40,"k"),(37,"l"),(44,"/")] {
                await WindowSwitcherRuntimeAudit.sendKey(code,to: panel,characters: text)
            }
            checks[prefix + "VimCharactersAreTextDuringSearch"] = model.sessionSearch == "hjkl/"
            await WindowSwitcherRuntimeAudit.sendKey(53,to: panel)
            checks[prefix + "EscapeClearsQueryWithoutLeavingSearchMode"] = model.isSearching && model.sessionSearch.isEmpty && panel.isVisible
            model.resetSessionSearch()
            model.selection = rows[0].id
            await WindowSwitcherRuntimeAudit.sendKey(26,to: panel,characters: "/",modifiers: .shift)
            checks[prefix + "ShiftRequiredLogicalSlashStartsSearch"] = model.isSearching && model.sessionSearch.isEmpty
            model.resetSessionSearch()
            await WindowSwitcherRuntimeAudit.sendKey(4,to: panel,characters: "H",modifiers: .shift)
            checks[prefix + "ShiftedLetterStartsTextSearch"] = model.sessionSearch == "H"
            evidence.append(["style": style.rawValue,"columns": columns,"windows": rows.count])
            controller.stopForModule()
        }
        // Arrow disabling consumes the key in the HUD; it must not move native button focus.
        defaults.set(false,forKey: SwitcherNavigationOptions.arrowsKey)
        defaults.set(false,forKey: SwitcherNavigationOptions.vimKey)
        let offModel = WindowSwitcherModel(windows: rows,permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: offModel)
        var titles = SwitcherShortcut.defaultOptionTab
        titles.presentation.style = .titles
        titles.releaseBehavior = .hold
        offModel.selection = rows[0].id
        if let panel = controller.beginVisualAudit(reduceTransparency: true,shortcut: titles) {
            let responder = panel.firstResponder
            for key: UInt16 in [123,124,125,126] { await WindowSwitcherRuntimeAudit.sendKey(key,to: panel) }
            checks["navigationDisabledArrowsDoNotMoveSelectionOrFocus"] = offModel.selection == rows[0].id && panel.firstResponder === responder && !offModel.isSearching
            await WindowSwitcherRuntimeAudit.sendKey(48,to: panel)
            checks["navigationTabWorksWithBothOptionsOff"] = offModel.selection == rows[1].id
            await WindowSwitcherRuntimeAudit.sendKey(48,to: panel,modifiers: .shift)
            checks["navigationShiftTabWorksWithBothOptionsOff"] = offModel.selection == rows[0].id
            await WindowSwitcherRuntimeAudit.sendKey(4,to: panel,characters: "h")
            checks["navigationVimOffKeepsLettersAsSearch"] = offModel.sessionSearch == "h"
        }
        controller.stopForModule()
        // Capture preferences once per session, including held modifiers and search-release routing.
        defaults.set(true,forKey: SwitcherNavigationOptions.vimKey)
        let catalog = NavigationAuditCatalog(rows), heldModel = WindowSwitcherModel(windows: rows,catalog: catalog,permitsCapture: { false })
        let held = WindowSwitcherHotkeyController(model: heldModel,foregroundApplication: { NSRunningApplication.current },modifierFlags: { .option })
        var heldShortcut = titles
        heldShortcut.releaseBehavior = .choose
        held.beginHeldAudit(shortcut: heldShortcut)
        checks["navigationHeldSessionFinishesPreparation"] = await wait { !held.preparingForAudit && held.auditPanel?.isVisible == true }
        if let panel = held.auditPanel {
            heldModel.selection = rows[0].id
            await WindowSwitcherRuntimeAudit.sendKey(37,to: panel,characters: "l",modifiers: .option)
            checks["navigationConsumesHeldOpeningOption"] = heldModel.selection == rows[1].id && !heldModel.isSearching
            defaults.set(false,forKey: SwitcherNavigationOptions.vimKey)
            await WindowSwitcherRuntimeAudit.sendKey(37,to: panel,characters: "l",modifiers: .option)
            checks["navigationPreferenceChangeDoesNotAlterCurrentSession"] = heldModel.selection == rows[2].id && held.activeNavigation?.vim == true
            await WindowSwitcherRuntimeAudit.sendKey(44,to: panel,characters: "/",modifiers: .option)
            held.releaseModifiersForAudit()
            let focused = await catalog.focused
            checks["navigationSearchPreventsReleaseFromCommitting"] = heldModel.isSearching && panel.isVisible && focused.isEmpty
        }
        held.stopForModule()
        _ = held.beginVisualAudit(reduceTransparency: true,shortcut: titles)
        checks["navigationNextSessionReadsNewPreference"] = held.activeNavigation?.vim == false
        held.stopForModule()
        checks["navigationStopClearsSessionOptionsAndInputResources"] = held.activeNavigation == nil && held.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        // User actions are explicit; do not silently clear them when navigation is enabled.
        defaults.set(true,forKey: SwitcherNavigationOptions.vimKey)
        let customModel = WindowSwitcherModel(windows: rows,permitsCapture: { false })
        let actions = WindowSwitcherHotkeyController(model: customModel)
        var bindings = SwitcherActionBinding.defaults
        bindings[bindings.firstIndex { $0.action == .search }!] = .init(action: .search,keyCode: 4)
        actions.saveActionBindings(bindings)
        customModel.selection = rows[1].id
        if let panel = actions.beginVisualAudit(reduceTransparency: true,shortcut: titles) {
            await WindowSwitcherRuntimeAudit.sendKey(4,to: panel,characters: "h")
            checks["navigationCustomActionPrecedesVim"] = customModel.isSearching && customModel.sessionSearch.isEmpty && customModel.selection == rows[1].id
            await WindowSwitcherRuntimeAudit.sendKey(4,to: panel,characters: "h")
            checks["navigationCustomBareActionBecomesTextInSearch"] = customModel.sessionSearch == "h"
            customModel.resetSessionSearch()
            bindings[bindings.firstIndex { $0.action == .search }!] = .init(action: .search,keyCode: 124)
            actions.saveActionBindings(bindings)
            await WindowSwitcherRuntimeAudit.sendKey(124,to: panel)
            checks["navigationCustomArrowWorksWithArrowNavigationOff"] = customModel.isSearching && customModel.sessionSearch.isEmpty
        }
        actions.stopForModule()
        SwitcherActionBindings.save(SwitcherActionBinding.defaults)
        // Queue a vertical and linear press while the real model waits for a new catalog.
        let waiting = NavigationAuditCatalog(rows,paused: true)
        let pendingModel = WindowSwitcherModel(windows: Array(rows.prefix(2)),catalog: waiting,permitsCapture: { false })
        let pending = WindowSwitcherHotkeyController(model: pendingModel,foregroundApplication: { NSRunningApplication.current },modifierFlags: { .option })
        var grid = titles
        grid.presentation.style = .thumbnails
        grid.presentation.autoSize = false
        pending.beginHeldAudit(shortcut: grid)
        let actuallyWaiting = await wait { await waiting.isWaiting }
        let visible = await wait { pending.auditPanel?.isVisible == true }
        checks["navigationQueuedCatalogActuallyWaits"] = actuallyWaiting && visible && pending.preparingForAudit
        if let panel = pending.auditPanel {
            await WindowSwitcherRuntimeAudit.sendKey(38,to: panel,characters: "j",modifiers: .option)
            await WindowSwitcherRuntimeAudit.sendKey(37,to: panel,characters: "l",modifiers: .option)
            await waiting.release()
            let done = await wait { !pending.preparingForAudit }
            let columns = pending.layout.columns
            checks["navigationQueuedDirectionsUseFreshGridInOrder"] = done && columns > 1 && columns + 1 < rows.count && pendingModel.selection == rows[columns + 1].id
        } else { await waiting.release()
        checks["navigationQueuedPanelExists"] = false }
        pending.stopForModule()
        evidence += await auditSettings(destination,checks: &checks)
        return evidence
    }
    private static func windows(_ count: Int) -> [SwitchableWindow] {
        (0..<count).map { index in .init(id: "nav-\(index)",processID: 1,application: "Fixture",title: "hjkl/ \(index)",applicationURL: nil,
            minimized: false,hidden: false,fullScreen: false,frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,
            canFullScreen: false,launchedAt: nil,lastFocusedAt: nil,windowID: UInt32(index+1)) }
    }
    private static func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < end { if await condition() { return true };try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }
    private static func auditSettings(_ destination: URL,checks: inout [String: Bool]) async -> [[String: Any]] {
        let suite = "MacPocket.NavigationSettingsAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { return [] }
        defer { defaults.removePersistentDomain(forName: suite) }
        var evidence: [[String: Any]] = []
        for width in [520.0,760.0] {
            defaults.set(true,forKey: SwitcherNavigationOptions.arrowsKey)
            defaults.set(false,forKey: SwitcherNavigationOptions.vimKey)
            let window = NSWindow(contentRect: NSRect(x: 100,y: 180,width: width,height: 360),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: Form { SwitcherNavigationSettings(bindings: SwitcherActionBinding.defaults,defaults: defaults) }
                .formStyle(.grouped).environment(\.locale,pocketLocale).preferredColorScheme(.light).background(Color(nsColor: .windowBackgroundColor)))
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(100))
            let prefix = "navigation-settings-\(Int(width))"
            let arrow = SwitcherAppearanceRuntimeAudit.press(String(localized: "Ok tuşlarıyla gezin"),in: window)
            let arrowChanged = await wait { !SwitcherNavigationOptions.load(defaults).arrows }
            checks[prefix + "NativeToggleDisablesArrows"] = arrow && arrowChanged
            let vim = SwitcherAppearanceRuntimeAudit.press(String(localized: "Vim tuşlarıyla gezin (h/j/k/l)"),in: window)
            let vimChanged = await wait { SwitcherNavigationOptions.load(defaults).vim }
            checks[prefix + "NativeToggleEnablesVim"] = vim && vimChanged
            // Let AppStorage's persisted state reach the native control before the snapshot.
            try? await Task.sleep(for: .milliseconds(100))
            let mappedH = (UInt16(0)...50).first { code in
                guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),virtualKey: code,keyDown: true) else { return false }
                return NSEvent(cgEvent: event)?.charactersIgnoringModifiers == "h"
            }
            if let mappedH {
                let conflict = SwitcherActionBinding(action: .search,keyCode: mappedH)
                window.contentView = NSHostingView(rootView: Form { SwitcherNavigationSettings(bindings: [conflict],defaults: defaults) }
                    .formStyle(.grouped).environment(\.locale,pocketLocale).preferredColorScheme(.light).background(Color(nsColor: .windowBackgroundColor)))
                try? await Task.sleep(for: .milliseconds(100))
                let value = WindowSwitcherRuntimeAudit.accessibilityValues(window).joined(separator: " ")
                let list = "\(conflict.displayName): \(conflict.action.localizedTitle)"
                checks[prefix + "ConflictWarningNamesTheCustomAction"] = value.contains(String(localized: "Özel eylemler gezinmeden önce uygulanır: \(list)"))
            } else { checks[prefix + "ConflictWarningNamesTheCustomAction"] = false }
            let nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix + "NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let w = Double(node["width"] ?? ""),w > 0 else { return false }
                return x < window.frame.minX - 2 || x + w > window.frame.maxX + 2
            }
            checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + ".png"))
            evidence.append(["width": width,"nodes": nodes])
            window.orderOut(nil)
        }
        return evidence
    }
}

private actor NavigationAuditCatalog: WindowCatalogServing {
    let windows: [SwitchableWindow]
    private var paused: Bool
    private var pending: CheckedContinuation<Void,Never>?
    private(set) var focused: [String] = []
    init(_ windows: [SwitchableWindow],paused: Bool = false) { self.windows = windows;self.paused = paused }
    var isWaiting: Bool { pending != nil }
    func release() { paused = false;pending?.resume();pending = nil }
    func snapshot() async -> WindowCatalogReport {
        if paused { await withCheckedContinuation { pending = $0 } }
        return .init(windows: windows,accessibilityGranted: true,partial: false)
    }
    func focus(_ id: String) async throws { focused.append(id) }
    func perform(_ action: WindowAction,on id: String) async throws { throw WindowCatalogError.unsupported }
    func noteApplicationActivation(_ pid: Int32) async {}
}
#endif
