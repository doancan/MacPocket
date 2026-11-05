#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

/// No global mouse interception or key posting: the real handler uses an injected action sink.
@MainActor enum MouseButtonRuntimeAudit {
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested else { return [:] }
        var checks: [String: Bool] = [:], actions: [MouseButtonBinding] = []
        let name = "com.doancan.MacPocket.MouseButtonAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { return ["mouseDefaults": false] }
        let service = MouseButtonService(defaults: defaults, usesHardware: false, dispatchAction: { actions.append($0) })
        defer { service.stopForModule(); defaults.removePersistentDomain(forName: name) }
        NSApp.activate(ignoringOtherApps: true)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 960, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        window.contentView = NSHostingView(rootView: MouseButtonsView(service: service))
        window.makeKeyAndOrderFront(nil)
        service.start()
        try? await Task.sleep(for: .milliseconds(200))
        checks["mouseDisabledByDefault"] = service.settings.enabled == false && service.moduleDiagnosticResources["tap"] == 0
        checks["mouseDisabledPassesInput"] = service.handle(.otherMouseDown, button(3))
        service.settings.enabled = true
        checks["mouseHandlerConsumesMappedDown"] = !service.handle(.otherMouseDown, button(3))
        checks["mouseHandlerConsumesMappedUp"] = !service.handle(.otherMouseUp, button(3))
        await settle()
        checks["mouseHandlerDispatchesBackOnce"] = actions.map(\.action) == [.back]
        checks["mouseUnmappedMiddlePassesThrough"] = service.handle(.otherMouseDown, button(2))

        service.settings.bindings["3"] = .init(.copy)
        _ = service.handle(.otherMouseDown, button(3)); _ = service.handle(.otherMouseDown, button(3))
        await settle()
        let count = actions.count
        service.settings.bindings["3"] = .init(.paste)
        checks["mousePairedDragSurvivesSettingsChange"] = !service.handle(.otherMouseDragged, button(3))
        checks["mousePairedUpSurvivesSettingsChange"] = !service.handle(.otherMouseUp, button(3))
        checks["mouseDuplicateDownDoesNotRepeat"] = count == 2 && actions.last?.action == .copy

        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "audit.app"
        service.settings.profiles[app] = ["3": .init(.forward)]
        _ = service.handle(.otherMouseDown, button(3)); _ = service.handle(.otherMouseUp, button(3)); await settle()
        checks["mouseApplicationProfileOverridesGlobal"] = actions.last?.action == .forward
        service.settings.excludedBundleIDs = [app]
        checks["mouseExcludedApplicationPassesThrough"] = service.handle(.otherMouseDown, button(3))
        service.settings.excludedBundleIDs = []
        service.settings.profiles[app]?["3"] = .init(.native)
        checks["mouseExplicitNativeOverridePassesThrough"] = service.handle(.otherMouseDown, button(3))
        service.settings.profiles[app] = nil
        service.settings.bindings["3"] = .init(.shortcut)
        checks["mouseIncompleteShortcutPassesThrough"] = service.handle(.otherMouseDown, button(3))
        service.settings.bindings["3"] = .init(.shelf)
        defaults.set(false, forKey: PocketModule.shelf.availabilityKey)
        checks["mouseDisabledTargetModulePassesThrough"] = service.handle(.otherMouseDown, button(3))
        service.settings.bindings["3"] = .init(.copy)
        service.recordingShortcut = true
        checks["mouseShortcutRecordingSuspendsBindings"] = service.handle(.otherMouseDown, button(3))
        service.recordingShortcut = false

        service.settings.bindings["100"] = .init(.copy)
        let wheel = wheelEvent(horizontal: 2, at: 1)
        service.diagnosticInstallClaims()
        checks["mouseMappedSideWheelClaimsBeforeScrollTransform"] = MouseInputClaims.claims(wheel)
        checks["mouseSideWheelConsumesInput"] = !service.handle(.scrollWheel, wheel)
        checks["mouseSideWheelChatterConsumed"] = !service.handle(.scrollWheel, wheelEvent(horizontal: 2, at: 1.01))
        let beforeWheel = actions.count
        await settle()
        checks["mouseSideWheelDispatchesOnce"] = actions.count == beforeWheel + 1
        let continuous = wheelEvent(horizontal: 2, at: 2); continuous.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        checks["mouseTrackpadScrollNotClaimed"] = service.handle(.scrollWheel, continuous) && !MouseInputClaims.claims(continuous)
        let synthetic = wheelEvent(horizontal: 2, at: 3); synthetic.setIntegerValueField(.eventSourceUserData, value: MouseScrollService.marker)
        checks["mouseSyntheticGlideIgnored"] = service.handle(.scrollWheel, synthetic) && !MouseInputClaims.claims(synthetic)

        let events = MouseButtonService.keyEvents(for: .init(keyCode: 8, modifiers: [.command, .shift]))
        checks["mouseGeneratedKeyPairBalanced"] = events.count == 2 && events.map(\.type) == [.keyDown, .keyUp]
        checks["mouseGeneratedKeyFlagsAndMarker"] = events.count == 2 && events.allSatisfy {
            $0.flags.contains([.maskCommand, .maskShift]) && !$0.flags.contains(.maskAlternate)
                && $0.getIntegerValueField(.keyboardEventKeycode) == 8 && $0.getIntegerValueField(.eventSourceUserData) == MouseButtonService.marker
        }
        checks["mouseBuiltinCommandCharactersMatchCurrentLayout"] = [(MouseButtonAction.back, "["), (.forward, "]"), (.copy, "c"), (.paste, "v")].allSatisfy { action, expected in
            let keys = MouseButtonService.keyEvents(for: MouseButtonBinding(action))
            // AppKit re-translates keyUp characters from the layout; commands execute on keyDown.
            return keys.count == 2 && NSEvent(cgEvent: keys[0])?.charactersIgnoringModifiers == expected
                && keys[0].type == .keyDown && keys[1].type == .keyUp
                && keys[0].getIntegerValueField(.keyboardEventKeycode) == keys[1].getIntegerValueField(.keyboardEventKeycode)
        }
        let physical = KeyCombo(keyCode: 33, modifiers: .command)
        let recorded = MouseButtonService.keyEvents(for: MouseButtonBinding(.shortcut, shortcut: physical))
        let unchanged = MouseButtonService.keyEvents(for: physical)
        checks["mouseRecordedShortcutKeepsPhysicalLayout"] = recorded.count == 2 && unchanged.count == 2
            && NSEvent(cgEvent: recorded[0])?.charactersIgnoringModifiers == NSEvent(cgEvent: unchanged[0])?.charactersIgnoringModifiers
        checks["mouseShortcutLabelUsesCurrentKeyboardLayout"] = unchanged.first.flatMap { NSEvent(cgEvent: $0)?.charactersIgnoringModifiers }.map {
            KeyComboPresentation.displayName(physical) == "⌘" + $0.uppercased()
        } == true

        let nodes = snapshot(window, to: destination.appendingPathExtension("mouse-buttons.png"))
        checks["mouseEnableSwitchAccessible"] = nodes.contains { $0["name"] == String(localized: "Fare tuşu atamalarını aç") }
        checks["mouseActionPickersAccessible"] = [3, 4].compactMap(MouseButtonInput.init(rawValue:)).allSatisfy { input in
            nodes.contains { $0["role"] == "AXPopUpButton" && $0["name"]?.contains(input.localizedTitle) == true }
        }

        service.beginCapture()
        checks["mouseCaptureOwnsMonitorAndTimeout"] = service.capturing && service.moduleDiagnosticResources["capture"] == 1 && service.moduleDiagnosticResources["captureTimer"] == 1
        checks["mouseCaptureSuspendsBindings"] = service.handle(.otherMouseDown, button(3))
        // Delivered to this audit window's normal AppKit event loop; no global event posting.
        let event = button(7); event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        if let native = NSEvent(cgEvent: event) { NSApp.postEvent(native, atStart: false) }
        await settle()
        checks["mouseLocalCaptureDetectsExtraButton"] = service.detected?.rawValue == 7 && !service.capturing
        service.stopCapture()

        let profileApp = Bundle.main.bundleIdentifier ?? "com.doancan.MacPocket.ModuleAudit"
        service.settings.profiles[profileApp] = ["3": .init(.shortcut, shortcut: .init(keyCode: 8, modifiers: .command)), "7": .init(.native)]
        service.settings.excludedBundleIDs = [profileApp]
        window.contentView = NSHostingView(rootView: MouseButtonsView(service: service, initialApplication: profileApp))
        window.setContentSize(NSSize(width: 760, height: 760)); await settle()
        _ = snapshot(window, to: destination.appendingPathExtension("mouse-profile.png"))
        service.settings.excludedBundleIDs = []
        service.settings.profiles[app] = nil
        service.settings.bindings["3"] = .init(.copy)
        service.diagnosticContextChanged(NSWorkspace.sessionDidResignActiveNotification)
        checks["mouseInactiveSessionPassesInput"] = service.handle(.otherMouseDown, button(3))
        service.diagnosticContextChanged(NSWorkspace.willSleepNotification)
        service.diagnosticContextChanged(NSWorkspace.didWakeNotification)
        checks["mouseWakeDoesNotReactivateInactiveSession"] = service.handle(.otherMouseDown, button(3))
        service.diagnosticContextChanged(NSWorkspace.sessionDidBecomeActiveNotification)
        checks["mouseSessionReturnResumesBindings"] = !service.handle(.otherMouseDown, button(3))
        _ = service.handle(.otherMouseUp, button(3)); await settle()
        let beforeSleep = actions.count
        _ = service.handle(.otherMouseDown, button(3))
        service.diagnosticContextChanged(NSWorkspace.willSleepNotification)
        service.diagnosticContextChanged(NSWorkspace.didWakeNotification); await settle()
        checks["mouseSleepCancelsDeferredAction"] = actions.count == beforeSleep
        let beforeStop = actions.count
        _ = service.handle(.otherMouseDown, button(3))
        service.beginCapture(); service.stopForModule(); await settle()
        checks["mouseModuleStopCancelsDeferredActions"] = actions.count == beforeStop
        checks["mouseModuleStopReleasesAllResources"] = service.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        checks["mouseModuleStopRemovesWheelClaims"] = !MouseInputClaims.claims(wheel)
        checks["mousePreferencesSurviveStop"] = MouseButtonSettings.load(from: defaults) == service.settings
        service.start(); service.diagnosticContextChanged(NSWorkspace.willSleepNotification); service.stopForModule()
        service.start()
        checks["mouseRestartClearsStaleSleepState"] = !service.handle(.otherMouseDown, button(3))
        service.stopForModule()
        checks["mouseRestartAndStopRemainClean"] = service.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        return checks
    }
    private static func button(_ number: Int) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: NSEvent.mouseLocation, mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number)); return event
    }
    private static func wheelEvent(horizontal: Int32, at time: Double) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: horizontal, wheel3: 0)!
        event.timestamp = UInt64(time * 1_000_000_000); return event
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(120)) }
    private static func snapshot(_ window: NSWindow, to destination: URL) -> [[String: String]] {
        let nodes = ToolUIAudit.accessibilityNodes(window)
        if let data = try? JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination.appendingPathExtension("ax.json"))
        }
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: destination)
        }
        return nodes
    }
}
#endif
