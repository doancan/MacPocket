#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

/// Real native panels/settings, with copied contact fixtures delivered through the production relay.
/// No hardware contact monitor, global gesture tap, actual haptic or external window focus is used.
@MainActor enum SwitcherGestureRuntimeAudit {
    private final class KeyboardFlags { var value: NSEvent.ModifierFlags = [] }
    static func run(destination: URL,checks: inout [String: Bool]) async -> [[String: Any]] {
        let name = "MacPocket.GestureAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { checks["gestureDefaultsExist"] = false;return [] }
        defer { defaults.removePersistentDomain(forName: name) }
        var evidence = await settings(destination,defaults: defaults,checks: &checks)
        let rows: [SwitchableWindow] = (0..<37).map { index in
            let pid: Int32 = index == 0 ? ProcessInfo.processInfo.processIdentifier : Int32(9000 + index)
            return SwitchableWindow(id: "gesture-\(index)",processID: pid,application: "Fixture",title: "Window \(index)",applicationURL: nil,
                minimized: false,hidden: false,fullScreen: false,frontmost: index == 0,windowAccessible: false,canClose: false,canMinimize: false,
                canFullScreen: false,launchedAt: nil,lastFocusedAt: nil,windowID: UInt32(index+1))
        }
        defaults.set(true,forKey: "switcher.globalEnabled")
        for style in SwitcherStyle.allCases {
            defaults.set(style == .icons ? 4 : 3,forKey: SwitcherGestureOptions.fingersKey)
            defaults.set("horizontal",forKey: SwitcherGestureOptions.axisKey)
            defaults.set(true,forKey: SwitcherGestureOptions.hapticsKey)
            var shortcut = SwitcherShortcut.defaultOptionTab
            shortcut.presentation.style = style
            shortcut.presentation.autoSize = false
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            SwitcherShortcutStore.save([shortcut],defaults)
            let catalog = GestureAuditCatalog(rows),monitor = GestureAuditMonitor()
            let model = WindowSwitcherModel(windows: rows,catalog: catalog,defaults: defaults,permitsCapture: { false })
            var feedback = 0
            let keyboardFlags = KeyboardFlags()
            let controller = WindowSwitcherHotkeyController(model: model,foregroundApplication: { NSRunningApplication.current },
                modifierFlags: { keyboardFlags.value },
                exceptionApplication: { .init(processID: 9000,launchedAt: nil,bundleIdentifier: "com.macpocket.GestureFixture",applicationPath: nil,name: "Gesture Fixture") },
                gestureMonitor: monitor,gestureSettings: defaults,gestureFeedback: { feedback += 1 })
            controller.beginGestureAudit()
            let prefix = "gesture-" + style.rawValue
            monitor.begin()
            monitor.frame(x: 0.38)
            checks[prefix + "OpensAndPreparesOwnedPanel"] = await wait { controller.auditPanel?.isVisible == true && !controller.preparingForAudit }
            checks[prefix + "HintExplainsFingerRelease"] = controller.sessionHint.contains(String(localized: "Parmakları kaldır: seç"))
            checks[prefix + "InitialSkipsForegroundWindow"] = model.selection == rows[1].id
            monitor.frame(x: 0.46)
            checks[prefix + "HorizontalMovesOneWindow"] = await wait { model.selection == rows[2].id }
            checks[prefix + "FeedbackOnlyOnSelectionChanges"] = feedback == 2
            monitor.frame(x: 0.47)
            await settle()
            checks[prefix + "SubthresholdDoesNotRepeatFeedback"] = feedback == 2 && model.selection == rows[2].id
            monitor.frame(x: 0.47,fingers: 2)
            await settle()
            checks[prefix + "PartialLiftKeepsPanelWithoutCommit"] = await catalog.focusCount == 0 && controller.auditPanel?.isVisible == true
            monitor.end()
            checks[prefix + "LastFingerCommitsOwnedSelection"] = await wait { await catalog.lastFocus == rows[2].id && controller.auditPanel?.isVisible != true }

            // Vertical motion uses the same row geometry as arrow/Vim navigation, including wrap.
            defaults.set("vertical",forKey: SwitcherGestureOptions.axisKey)
            controller.updateGestureSettingsForAudit()
            monitor.begin()
            monitor.frame(y: 0.22)
            checks[prefix + "VerticalOpens"] = await wait { controller.auditPanel?.isVisible == true && !controller.preparingForAudit }
            let columns = controller.layout.columns
            monitor.frame(y: 0.14)
            checks[prefix + "VerticalMovesDownOneRow"] = await wait { model.selection == rows[min(columns+1,rows.count-1)].id }
            monitor.frame(y: 0.24)
            checks[prefix + "VerticalReversalMovesUpOneRow"] = await wait { model.selection == rows[1].id }
            if let panel = controller.auditPanel { await WindowSwitcherRuntimeAudit.sendKey(53,to: panel) }
            monitor.frame(y: 0.08)
            monitor.end()
            await settle()
            checks[prefix + "EscapeDoesNotReopenOrCommitHeldGesture"] = await catalog.focusCount == 1 && controller.auditPanel?.isVisible != true

            // A gesture beginning over an existing keyboard session must never take its ownership.
            _ = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut)
            let keyboardSelection = model.selection
            monitor.begin()
            monitor.frame(y: 0.22)
            monitor.end()
            await settle()
            checks[prefix + "GestureCannotTakeOverKeyboardPanel"] = await catalog.focusCount == 1 && controller.auditPanel?.isVisible == true && model.selection == keyboardSelection && !controller.gestureOwnedForAudit
            controller.dismissForAudit()

            monitor.begin()
            monitor.frame(y: 0.22)
            _ = await wait { controller.auditPanel?.isVisible == true && !controller.preparingForAudit }
            if let panel = controller.auditPanel { await WindowSwitcherRuntimeAudit.sendKey(13,to: panel,characters: "w") }
            monitor.end()
            await settle()
            checks[prefix + "TypingKeepsSearchOpenOnFingerRelease"] = await catalog.focusCount == 1 && controller.auditPanel?.isVisible == true && model.isSearching && model.sessionSearch == "w"
            controller.dismissForAudit()

            monitor.begin()
            monitor.frame(y: 0.22)
            _ = await wait { controller.auditPanel?.isVisible == true && !controller.preparingForAudit }
            let feedbackBeforeOff = feedback
            defaults.set(false,forKey: SwitcherGestureOptions.hapticsKey)
            controller.updateGestureSettingsForAudit()
            monitor.frame(y: 0.14)
            monitor.end()
            await settle()
            checks[prefix + "SettingChangeCancelsWithoutCommit"] = await catalog.focusCount == 1 && controller.auditPanel?.isVisible != true
            monitor.begin()
            monitor.frame(y: 0.22)
            _ = await wait { controller.auditPanel?.isVisible == true && !controller.preparingForAudit }
            monitor.frame(y: 0.14)
            await settle()
            checks[prefix + "FeedbackOffStillNavigates"] = model.selection == rows[min(columns+1,rows.count-1)].id && feedback == feedbackBeforeOff
            monitor.cancel()
            await settle()
            checks[prefix + "InvalidFrameCancelsWithoutCommit"] = await catalog.focusCount == 1 && controller.auditPanel?.isVisible != true

            defaults.set(false,forKey: "switcher.globalEnabled")
            controller.updateGestureSettingsForAudit()
            monitor.begin()
            monitor.frame(y: 0.22)
            monitor.end()
            await settle()
            checks[prefix + "GlobalOffStopsMonitorAndPanel"] = !monitor.isRunning && controller.auditPanel?.isVisible != true
            defaults.set(true,forKey: "switcher.globalEnabled")
            controller.updateGestureSettingsForAudit()
            _ = controller.setRecording(true)
            controller.updateGestureSettingsForAudit()
            checks[prefix + "RecorderStopsGestureInput"] = !monitor.isRunning
            _ = controller.setRecording(false)
            controller.updateGestureSettingsForAudit()
            _ = SwitcherExceptionStore.save([.init(target: .bundleIdentifier,value: "com.macpocket.GestureFixture",shortcuts: .alwaysDisable)],defaults)
            controller.updateExceptionsForAudit()
            controller.updateGestureSettingsForAudit()
            monitor.begin()
            monitor.frame(y: 0.22)
            monitor.end()
            await settle()
            checks[prefix + "ForegroundExceptionStopsGestureInput"] = controller.suspendedForApplication != nil && !monitor.isRunning && controller.auditPanel?.isVisible != true
            _ = SwitcherExceptionStore.save([],defaults)
            controller.updateExceptionsForAudit()
            controller.updateGestureSettingsForAudit()
            monitor.begin()
            monitor.frame(y: 0.22)
            checks[prefix + "KeyboardTakeoverStartsWithGesturePanel"] = await wait { controller.gestureOwnedForAudit && controller.auditPanel?.isVisible == true && !controller.preparingForAudit }
            keyboardFlags.value = .option
            controller.beginHeldAudit(shortcut: shortcut)
            checks[prefix + "KeyboardTakeoverRestoresProfileReleaseAndMovesOnce"] = !controller.gestureOwnedForAudit && controller.activeShortcut?.releaseBehavior == .choose && model.selection == rows[2].id
            monitor.cancel()
            monitor.end()
            await settle()
            let countBeforeKeyboardRelease = await catalog.focusCount
            checks[prefix + "OldGestureCancelAndReleaseCannotCloseKeyboardPanel"] = controller.auditPanel?.isVisible == true && countBeforeKeyboardRelease == 1
            keyboardFlags.value = []
            checks[prefix + "KeyboardTakeoverModifierReleaseCommitsOnce"] = await wait {
                let count = await catalog.focusCount,focus = await catalog.lastFocus
                return count == 2 && focus == rows[2].id && controller.auditPanel?.isVisible != true
            }
            controller.stopForModule()
            monitor.begin()
            monitor.frame(y: 0.22)
            await settle()
            checks[prefix + "StopReleasesAllResourcesAndRejectsLateFrames"] = !monitor.isRunning && controller.auditPanel?.isVisible != true && controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
            evidence.append(["style": style.rawValue,"columns": columns,"feedbackRequests": feedback,"contactSource": "copied-fixture-values","hardwareVerified": false])
        }
        return evidence
    }
    private static func settings(_ destination: URL,defaults: UserDefaults,checks: inout [String: Bool]) async -> [[String: Any]] {
        var evidence: [[String: Any]] = []
        for width in [520.0,760.0] {
            defaults.set(0,forKey: SwitcherGestureOptions.fingersKey)
            defaults.set("horizontal",forKey: SwitcherGestureOptions.axisKey)
            defaults.set(false,forKey: SwitcherGestureOptions.hapticsKey)
            let window = NSWindow(contentRect: NSRect(x: 120,y: 150,width: width,height: 560),styleMask: [.titled,.closable],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            func render(_ available: Bool) {
                window.contentView = NSHostingView(rootView: Form { SwitcherGestureSettings(isAvailable: available,defaults: defaults) }
                    .formStyle(.grouped).environment(\.locale,pocketLocale).preferredColorScheme(.light))
                window.makeKeyAndOrderFront(nil)
            }
            render(true)
            await settle()
            let prefix = "gesture-settings-\(Int(width))"
            for (label,count) in [(String(localized: "Üç parmakla kaydır"),3),(String(localized: "Dört parmakla kaydır"),4)] {
                let pressed = SwitcherAppearanceRuntimeAudit.press(label,in: window,role: .radioButton)
                let changed = await wait { SwitcherGestureOptions.load(defaults).fingers == count }
                checks[prefix + "FingerChoice\(count)"] = pressed && changed
            }
            for axis in [SwitcherGestureAxis.vertical,.horizontal] {
                let pressed = SwitcherAppearanceRuntimeAudit.press(axis.localizedTitle,in: window,role: .radioButton)
                let changed = await wait { SwitcherGestureOptions.load(defaults).axis == axis }
                checks[prefix + "Axis-" + axis.rawValue] = pressed && changed
            }
            let pressed = SwitcherAppearanceRuntimeAudit.press(String(localized: "Seçim değiştiğinde haptik geri bildirim"),in: window)
            let changed = await wait { SwitcherGestureOptions.load(defaults).haptics }
            checks[prefix + "HapticTogglePersists"] = pressed && changed
            await settle()
            let enabledStates = controlStates(window)
            checks[prefix + "AvailableControlsEnabled"] = enabledStates.count == 6 && enabledStates.allSatisfy { $0 }
            let nodes = ToolUIAudit.accessibilityNodes(window)
            checks[prefix + "NoMeasuredHorizontalOverflow"] = !nodes.contains { node in
                guard let x = Double(node["x"] ?? ""),let w = Double(node["width"] ?? ""),w > 0 else { return false }
                return x < window.frame.minX - 2 || x + w > window.frame.maxX + 2
            }
            checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + ".png"))
            evidence.append(["width": width,"nodes": nodes])
            render(false)
            await settle()
            let unavailable = controlStates(window)
            checks[prefix + "UnavailableControlsDisabled"] = unavailable.count == 6 && unavailable.allSatisfy { !$0 }
            evidence.append(["width": width,"unavailableControlEnabledStates": unavailable])
            checks[prefix + "UnavailableSnapshot"] = WindowSwitcherRuntimeAudit.snapshot(window,to: destination.appendingPathComponent(prefix + "-unavailable.png"))
            window.orderOut(nil)
        }
        return evidence
    }
    private static func controlStates(_ root: NSObject) -> [Bool] {
        var pending = [root],seen = Set<ObjectIdentifier>(),states: [Bool] = []
        while let node = pending.popLast(),seen.count < 2000 {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            let roleSelector = NSSelectorFromString("accessibilityRole")
            let role = node.responds(to: roleSelector) ? node.perform(roleSelector)?.takeUnretainedValue() as? String : nil
            if [NSAccessibility.Role.radioButton.rawValue,NSAccessibility.Role.checkBox.rawValue].contains(role ?? "") {
                let attribute = NSSelectorFromString("accessibilityAttributeValue:")
                if node.responds(to: attribute),let enabled = node.perform(attribute,with: NSAccessibility.Attribute.enabled.rawValue)?.takeUnretainedValue() as? NSNumber {
                    states.append(enabled.boolValue)
                } else if let accessible = node as? any NSAccessibilityProtocol { states.append(accessible.isAccessibilityEnabled()) }
                else {
                    for name in ["isAccessibilityEnabled","accessibilityEnabled"] {
                        let selector = NSSelectorFromString(name)
                        if node.responds(to: selector) {
                            typealias Enabled = @convention(c) (AnyObject,Selector) -> ObjCBool
                            states.append(unsafeBitCast(node.method(for: selector),to: Enabled.self)(node,selector).boolValue)
                            break
                        }
                    }
                }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children) { pending += node.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] }
        }
        return states
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(120)) }
    private static func wait(_ condition: @MainActor () async -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < end { if await condition() { return true };try? await Task.sleep(for: .milliseconds(20)) }
        return false
    }
}

@MainActor private final class GestureAuditMonitor: SwitcherGestureMonitoring {
    let relay = TrackpadGestureRelay()
    var isAvailable: Bool { true }
    private(set) var isRunning = false
    private var fingers = 3
    func configure(options: SwitcherGestureOptions,receive: @escaping @MainActor (SwitcherGestureEvent) -> Void) {
        isRunning = options.enabled
        fingers = options.fingers
        relay.configure(options: options,devices: [1],receive: receive)
    }
    func stop() { isRunning = false;relay.stop() }
    func begin() { end();frame() }
    func frame(x: Double = 0.3,y: Double = 0.3,fingers: Int? = nil) {
        relay.process(device: 1,contacts: (1...max(1,fingers ?? self.fingers)).map { .init(id: Int32($0),x: x,y: y) })
    }
    func end() { relay.process(device: 1,contacts: []) }
    func cancel() { relay.process(device: 1,contacts: nil) }
}
private actor GestureAuditCatalog: WindowCatalogServing {
    let rows: [SwitchableWindow]
    private(set) var lastFocus: String?
    private(set) var focusCount = 0
    init(_ rows: [SwitchableWindow]) { self.rows = rows }
    func snapshot() async -> WindowCatalogReport { .init(windows: rows,accessibilityGranted: true,partial: false) }
    func focus(_ id: String) async throws { guard rows.contains(where: { $0.id == id }) else { throw WindowCatalogError.expired };lastFocus = id;focusCount += 1 }
    func perform(_ action: WindowAction,on id: String) async throws { throw WindowCatalogError.expired }
    func noteApplicationActivation(_ pid: Int32) async {}
}
#endif
