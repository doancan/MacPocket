#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

private actor HoldAuditCatalog: WindowCatalogServing {
    let rows: [SwitchableWindow]
    private var paused: Bool
    private var pending: CheckedContinuation<Void,Never>?
    private(set) var focused: [String] = []
    init(_ rows: [SwitchableWindow],paused: Bool = false) { self.rows = rows;self.paused = paused }
    var waiting: Bool { pending != nil }
    func release() { paused = false;pending?.resume();pending = nil }
    func snapshot() async -> WindowCatalogReport {
        if paused { await withCheckedContinuation { pending = $0 } }
        return .init(windows: rows,accessibilityGranted: true,partial: false)
    }
    func focus(_ id: String) async throws { focused.append(id) }
    func perform(_ action: WindowAction,on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

@MainActor enum SwitcherHoldRuntimeAudit {
    private final class Flags { var value: NSEvent.ModifierFlags = [.control,.option] }
    private final class Settings: ObservableObject {
        @Published var shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: [.control,.option])
        @Published var enabled = true
    }
    private struct SettingsForm: View {
        @ObservedObject var state: Settings
        var body: some View {
            Form { SwitcherHoldOptions(shortcut: state.shortcut,update: { state.shortcut = $0 }).disabled(!state.enabled) }
                .formStyle(.grouped).environment(\.locale,pocketLocale)
                .overlay(alignment: .bottomTrailing) {
                    SwitcherShortcutPresets(shortcut: state.shortcut,update: { state.shortcut = $0 })
                        .disabled(!state.enabled).padding(16)
                }
        }
    }
    static func run(destination: URL,checks: inout [String:Bool]) async throws -> [[String:Any]] {
        let evidence = await settings(destination,checks: &checks)
        let rows: [SwitchableWindow] = (0..<5).map { (index: Int) -> SwitchableWindow in
            let pid: Int32 = index == 0 ? getpid() : Int32(9000+index)
            return SwitchableWindow(id: "hold-\(index)",processID: pid,application: "Hold Fixture",title: "Window \(index)",applicationURL: nil,
                minimized: false,hidden: false,fullScreen: false,frontmost: index == 0,windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,
                launchedAt: nil,lastFocusedAt: nil,windowID: UInt32(index+1))
        }
        for style in SwitcherStyle.allCases {
            let flags = Flags(),catalog = HoldAuditCatalog(rows)
            let model = WindowSwitcherModel(windows: rows,catalog: catalog,permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model,foregroundApplication: { NSRunningApplication.current },modifierFlags: { flags.value })
            var shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: [.control,.option],holdModifiers: .option)
            shortcut.presentation.style = style
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            controller.beginHeldAudit(shortcut: shortcut)
            let prefix = "hold-"+style.rawValue
            checks[prefix+"PreparedNativePanel"] = await wait { !controller.preparingForAudit && controller.auditPanel?.isVisible == true }
            checks[prefix+"HintNamesOnlyOwnedModifier"] = controller.sessionHint.contains("⌥") && !controller.sessionHint.contains("⌃")
            if let panel = controller.auditPanel {
                flags.value = .option
                await sendFlags(.option,to: panel)
                let before = await catalog.focused
                checks[prefix+"OpeningOnlyModifierReleaseDoesNotChoose"] = panel.isVisible && before.isEmpty
                model.selection = rows[1].id
                await WindowSwitcherRuntimeAudit.sendKey(SwitcherKeys.tab,to: panel,modifiers: .option)
                checks[prefix+"OptionTabMovesForward"] = model.selection == rows[2].id
                await WindowSwitcherRuntimeAudit.sendKey(SwitcherKeys.tab,to: panel,modifiers: [.option,.shift])
                checks[prefix+"OptionShiftTabMovesBackward"] = model.selection == rows[1].id
                // The opening-only Control remains held; releasing Option must still commit.
                flags.value = .control
                await sendFlags(.control,to: panel)
                checks[prefix+"OwnedModifierReleaseChoosesWithControlStillDown"] = await wait { await catalog.focused == [rows[1].id] && !panel.isVisible }
                await sendFlags([],to: panel)
                let after = await catalog.focused
                checks[prefix+"LaterModifierReleaseCannotChooseAgain"] = after == [rows[1].id]
            }
            controller.stopForModule()
            checks[prefix+"StopReleasesAllInputResources"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        }
        // Command ownership uses the ordinary panel path. These are local AppKit events,
        // not a claim about delivery of the reserved system shortcut or physical HID.
        for behavior in [SwitcherReleaseBehavior.choose,.search,.hold] {
            let flags = Flags(),catalog = HoldAuditCatalog(rows)
            flags.value = .command
            let model = WindowSwitcherModel(windows: rows,catalog: catalog,permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model,foregroundApplication: { NSRunningApplication.current },modifierFlags: { flags.value })
            var shortcut = SwitcherShortcut(keyCode: 48,modifiers: .command,releaseBehavior: behavior)
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            let prefix = "holdCommand-"+behavior.rawValue
            controller.beginHeldAudit(shortcut: shortcut)
            checks[prefix+"Prepared"] = await wait { !controller.preparingForAudit && controller.auditPanel?.isVisible == true }
            if let panel = controller.auditPanel {
                model.selection = rows[1].id
                await WindowSwitcherRuntimeAudit.sendKey(48,to: panel,modifiers: .command)
                checks[prefix+"Forward"] = model.selection == rows[2].id
                await WindowSwitcherRuntimeAudit.sendKey(48,to: panel,modifiers: [.command,.shift])
                checks[prefix+"Reverse"] = model.selection == rows[1].id
                if behavior == .search {
                    await WindowSwitcherRuntimeAudit.sendKey(1,to: panel,characters: "s",modifiers: .command)
                    checks[prefix+"CommandActionWhileHeld"] = model.isSearching && panel.isVisible
                    await WindowSwitcherRuntimeAudit.sendKey(13,to: panel,characters: "w",modifiers: .command)
                    checks[prefix+"SearchTypingIgnoresHeldCommand"] = model.sessionSearch == "w" && panel.isVisible
                }
                flags.value = []
                await sendFlags([],to: panel)
                if behavior == .choose {
                    checks[prefix+"Release"] = await wait { await catalog.focused == [rows[1].id] && !panel.isVisible }
                } else {
                    let focused = await catalog.focused
                    checks[prefix+"Release"] = panel.isVisible && focused.isEmpty && (behavior != .search || model.isSearching)
                }
            }
            controller.stopForModule()
            checks[prefix+"Stopped"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        }
        for release in [true,false] {
            let flags = Flags(),catalog = HoldAuditCatalog(rows)
            flags.value = .command
            let model = WindowSwitcherModel(windows: rows,catalog: catalog,permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model,modifierFlags: { flags.value })
            var shortcut = SwitcherShortcut(keyCode: 48,modifiers: .command)
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            controller.beginHeldAudit(shortcut: shortcut)
            let prefix = "holdCommandLost-"+(release ? "release" : "enter")
            checks[prefix+"Prepared"] = await wait { !controller.preparingForAudit && controller.auditPanel?.isVisible == true }
            controller.loseNativeKeysForAudit()
            if let panel = controller.auditPanel {
                if release { flags.value = [];await sendFlags([],to: panel) }
                else { await WindowSwitcherRuntimeAudit.sendKey(36,to: panel,modifiers: .command) }
                let focused = await catalog.focused
                checks[prefix+"CancelsWithoutFocusing"] = !panel.isVisible && focused.isEmpty
            }
            controller.stopForModule()
        }
        // An archive without the override must retain the previous all-modifiers release rule.
        let legacyFlags = Flags(),legacyCatalog = HoldAuditCatalog(rows)
        let legacyModel = WindowSwitcherModel(windows: rows,catalog: legacyCatalog,permitsCapture: { false })
        let legacyController = WindowSwitcherHotkeyController(model: legacyModel,foregroundApplication: { NSRunningApplication.current },modifierFlags: { legacyFlags.value })
        var legacy = SwitcherShortcut(keyCode: 48,modifiers: [.control,.option])
        legacy.presentation.animateOpening = false
        legacy.presentation.animateClosing = false
        legacyController.beginHeldAudit(shortcut: legacy)
        _ = await wait { !legacyController.preparingForAudit && legacyController.auditPanel?.isVisible == true }
        if let panel = legacyController.auditPanel {
            legacyFlags.value = .control
            await sendFlags(.control,to: panel)
            let focused = await legacyCatalog.focused
            checks["holdLegacyStillWaitsForAllOpeningModifiers"] = panel.isVisible && focused.isEmpty
            legacyFlags.value = []
            await sendFlags([],to: panel)
            checks["holdLegacyChoosesAfterLastOpeningModifier"] = await wait { await legacyCatalog.focused == [rows[1].id] && !panel.isVisible }
        }
        legacyController.stopForModule()
        // Fast release while a fresh scan is pending must not wait for the display delay.
        let flags = Flags(),gate = HoldAuditCatalog(rows,paused: true)
        let model = WindowSwitcherModel(windows: rows,catalog: gate,permitsCapture: { false })
        let controller = WindowSwitcherHotkeyController(model: model,foregroundApplication: { NSRunningApplication.current },modifierFlags: { flags.value })
        var delayed = SwitcherShortcut(keyCode: SwitcherKeys.tab,modifiers: [.control,.option],holdModifiers: .option)
        delayed.presentation.openingDelayMilliseconds = 900
        delayed.presentation.animateOpening = false
        delayed.presentation.animateClosing = false
        controller.beginHeldAudit(shortcut: delayed)
        checks["holdColdCatalogIsWaiting"] = await wait { await gate.waiting }
        flags.value = .control
        try await Task.sleep(for: .milliseconds(40))
        checks["holdFastReleaseKeepsDelayedPanelHidden"] = controller.auditPanel?.isVisible != true
        await gate.release()
        checks["holdFastReleaseCommitsFreshTargetOnce"] = await wait { await gate.focused == [rows[1].id] && controller.auditPanel?.isVisible != true }
        controller.stopForModule()
        for behavior in [SwitcherReleaseBehavior.search,.hold] {
            let flags = Flags(),catalog = HoldAuditCatalog(rows)
            let model = WindowSwitcherModel(windows: rows,catalog: catalog,permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model,modifierFlags: { flags.value })
            var shortcut = SwitcherShortcut(keyCode: 48,modifiers: [.control,.option],releaseBehavior: behavior,holdModifiers: .option)
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            controller.beginHeldAudit(shortcut: shortcut)
            _ = await wait { !controller.preparingForAudit && controller.auditPanel?.isVisible == true }
            if let panel = controller.auditPanel {
                flags.value = .control
                await sendFlags(.control,to: panel)
                let focused = await catalog.focused
                checks["holdRelease-"+behavior.rawValue+"KeepsPanelWithoutFocus"] = panel.isVisible && focused.isEmpty && (behavior != .search || model.isSearching)
                await WindowSwitcherRuntimeAudit.sendKey(SwitcherKeys.escape,to: panel)
                checks["holdRelease-"+behavior.rawValue+"EscapeCancels"] = !panel.isVisible
            }
            controller.stopForModule()
        }
        for behavior in [SwitcherReleaseBehavior.choose,.search,.hold] {
            let flags = Flags(),catalog = HoldAuditCatalog(rows)
            flags.value = .option
            let model = WindowSwitcherModel(windows: rows,catalog: catalog,permitsCapture: { false })
            let controller = WindowSwitcherHotkeyController(model: model,modifierFlags: { flags.value })
            var shortcut = SwitcherShortcut(keyCode: 48,modifiers: .option,releaseBehavior: behavior)
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            _ = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut)
            model.selection = rows[0].id
            controller.beginHeldAudit(shortcut: shortcut)
            let prefix = "holdManualTakeover-"+behavior.rawValue
            checks[prefix+"MovesExactlyOneWindow"] = model.selection == rows[1].id
            if let panel = controller.auditPanel {
                flags.value = []
                await sendFlags([],to: panel)
                if behavior == .choose {
                    checks[prefix+"ReleaseChooses"] = await wait { await catalog.focused == [rows[1].id] && !panel.isVisible }
                } else {
                    let focused = await catalog.focused
                    checks[prefix+"ReleaseKeepsExpectedMode"] = panel.isVisible && (behavior != .search || model.isSearching) && focused.isEmpty
                }
            }
            controller.stopForModule()
            checks[prefix+"StopReleasesResources"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        }
        // A keyboard takeover during the manual preview's scan must commit its fresh result,
        // including the queued Tab step, after a quick modifier release.
        let takeoverFlags = Flags(),takeoverCatalog = HoldAuditCatalog(rows,paused: true)
        takeoverFlags.value = .option
        let takeoverModel = WindowSwitcherModel(windows: rows,catalog: takeoverCatalog,permitsCapture: { false })
        let takeoverController = WindowSwitcherHotkeyController(model: takeoverModel,modifierFlags: { takeoverFlags.value })
        var takeoverShortcut = SwitcherShortcut.defaultOptionTab
        takeoverShortcut.presentation.animateOpening = false
        takeoverShortcut.presentation.animateClosing = false
        _ = takeoverController.beginVisualAudit(reduceTransparency: true,shortcut: takeoverShortcut)
        takeoverController.dismissForAudit()
        takeoverController.show(shortcut: takeoverShortcut)
        checks["holdManualColdTakeoverScanIsPending"] = await wait { await takeoverCatalog.waiting }
        takeoverController.beginHeldAudit(shortcut: takeoverShortcut)
        takeoverFlags.value = []
        if let panel = takeoverController.auditPanel { await sendFlags([],to: panel) }
        checks["holdManualColdTakeoverDoesNotFocusStaleSnapshot"] = (await takeoverCatalog.focused).isEmpty
        await takeoverCatalog.release()
        checks["holdManualColdTakeoverCommitsQueuedStepOnce"] = await wait { await takeoverCatalog.focused == [rows[1].id] && takeoverController.auditPanel?.isVisible != true }
        takeoverController.stopForModule()
        return evidence
    }
    private static func settings(_ destination: URL,checks: inout [String:Bool]) async -> [[String:Any]] {
        var evidence: [[String:Any]] = []
        for width in [520.0,760.0] {
            let state = Settings(),window = NSWindow(contentRect: NSRect(x: 120,y: 160,width: width,height: 430),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsForm(state: state))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            _ = await wait { window.isKeyWindow && NSApp.isActive }
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(180))
            let label = String(localized: "Basılı tutulan tuşlar")
            let diagnostic = actionDetails(window)
            let expanded = press(label,in: window,role: .disclosureTriangle)
            _ = await wait { ToolUIAudit.accessibilityNodes(window).contains { $0["role"] == NSAccessibility.Role.radioButton.rawValue } }
            let selected = press(String(localized: "Yalnız \("⌥")"),in: window,role: .radioButton)
            await settle()
            let prefix = "holdSettings-\(Int(width))"
            checks[prefix+"NativeRadioUpdatesHoldSet"] = expanded && selected && state.shortcut.holdModifiers == .option
            let restored = press(String(localized: "Açma kısayolunu izle"),in: window,role: .radioButton)
            await settle()
            checks[prefix+"NativeRadioRestoresDefault"] = restored && state.shortcut.holdModifiers == nil
            let nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix+"PresetMenuHasLocalizedName"] = nodes.contains {
                $0["name"] == String(localized: "Hazır kısayollar") && ["AXMenuButton","AXPopUpButton"].contains($0["role"] ?? "")
            }
            checks[prefix+"NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let width = Double(node["width"] ?? ""),width > 0 else { return false }
                return x < window.frame.minX-2 || x+width > window.frame.maxX+2
            }
            checks[prefix+"Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix+".png"))
            state.enabled = false
            await settle()
            _ = press(String(localized: "Yalnız \("⌥")"),in: window,role: .radioButton)
            await settle()
            checks[prefix+"DisabledRecorderCannotChangeHoldSet"] = state.shortcut.holdModifiers == nil
            evidence.append(["width": width,"nodes": nodes,"beforeActions": diagnostic,"expandedPressFound": expanded,"radioPressFound": selected])
            window.orderOut(nil)
        }
        return evidence
    }
    private static func press(_ label: String,in root: NSWindow,role: NSAccessibility.Role) -> Bool {
        var pending: [NSObject] = [root]
        var seen = Set<ObjectIdentifier>()
        while let node = pending.popLast(),seen.count < 2000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            func get(_ name: String) -> Any? {
                let selector = NSSelectorFromString(name)
                return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() : nil
            }
            let labels = ["accessibilityLabel","accessibilityTitle","accessibilityDescription"].compactMap { get($0) as? String }
            let action = NSSelectorFromString("accessibilityPerformAction:")
            if get("accessibilityRole") as? String == role.rawValue,labels.contains(label),node.responds(to: action) {
                func click(_ local: CGPoint) {
                    root.makeKeyAndOrderFront(nil)
                    for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type,location: local,modifierFlags: [],timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: root.windowNumber,context: nil,eventNumber: 1,clickCount: 1,pressure: type == .leftMouseDown ? 1 : 0) { NSApp.postEvent(event,atStart: false) }
                    }
                }
                if role == .disclosureTriangle,let content = root.contentView {
                    // This owned form has one first-row disclosure; its virtual AX wrapper does
                    // not dispatch press. Exercise the ordinary AppKit hit path inside our window.
                    // Measured chevron centers for the two owned fixture widths; grouped Form
                    // changes its horizontal inset between 520 and 760 pt.
                    click(CGPoint(x: content.bounds.width < 640 ? 32 : 40,y: content.bounds.height-42))
                    return true
                }
                let frameSelector = NSSelectorFromString("accessibilityFrame")
                if node.responds(to: frameSelector) {
                    typealias Frame = @convention(c) (AnyObject,Selector) -> CGRect
                    let frame = unsafeBitCast(node.method(for: frameSelector),to: Frame.self)(node,frameSelector)
                    let center = CGPoint(x: frame.midX,y: frame.midY)
                    if frame.width > 0,frame.height > 0,root.frame.contains(center) {
                        let local = root.convertPoint(fromScreen: center)
                        click(local)
                        return true
                    }
                }
                typealias Perform = @convention(c) (AnyObject,Selector,NSString) -> Void
                unsafeBitCast(node.method(for: action),to: Perform.self)(node,action,NSAccessibility.Action.press.rawValue as NSString)
                return true
            }
            pending += get("accessibilityChildren") as? [NSObject] ?? []
        }
        return false
    }
    private static func actionDetails(_ root: NSObject) -> [[String:Any]] {
        var pending = [root],seen = Set<ObjectIdentifier>(),result: [[String:Any]] = []
        while let node = pending.popLast(),seen.count < 2000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            func get(_ name: String) -> Any? {
                let selector = NSSelectorFromString(name)
                return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() : nil
            }
            if get("accessibilityRole") as? String == NSAccessibility.Role.disclosureTriangle.rawValue {
                result.append(["class": String(describing: type(of: node)),"actions": get("accessibilityActionNames") ?? [],
                    "press": node.responds(to: NSSelectorFromString("accessibilityPerformPress")),"informal": node.responds(to: NSSelectorFromString("accessibilityPerformAction:")),
                    "expand": node.responds(to: NSSelectorFromString("accessibilityPerformExpand")),"setExpanded": node.responds(to: NSSelectorFromString("setAccessibilityExpanded:")),
                    "pick": node.responds(to: NSSelectorFromString("accessibilityPerformPick")),"frameGetter": node.responds(to: NSSelectorFromString("accessibilityFrame")),"label": get("accessibilityLabel") ?? "","title": get("accessibilityTitle") ?? ""])
            }
            pending += get("accessibilityChildren") as? [NSObject] ?? []
        }
        return result
    }
    private static func sendFlags(_ flags: NSEvent.ModifierFlags,to window: NSWindow) async {
        if let event = NSEvent.keyEvent(with: .flagsChanged,location: .zero,modifierFlags: flags,timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,context: nil,characters: "",charactersIgnoringModifiers: "",isARepeat: false,keyCode: 58) { NSApp.sendEvent(event) }
        await settle()
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(70)) }
    private static func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < end { if await condition() { return true };try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }
}
#endif
