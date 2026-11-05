#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class ModuleServiceProbe {
    static private(set) var created: Set<String> = []
    init(_ name: String) { Self.created.insert(name) }
}

/// Runs only in an explicitly isolated audit bundle. Never edits the installed app's preferences.
@MainActor
enum ModuleRuntimeAudit {
    private static var previewWindow: NSWindow?
    static var requested: Bool {
        CommandLine.arguments.contains("--audit-modules") && Bundle.main.bundleIdentifier?.hasSuffix(".ModuleAudit") == true
    }

    static func dataURL(_ name: String) -> URL? {
        guard requested, let index = CommandLine.arguments.firstIndex(of: "--audit-modules"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1]).deletingLastPathComponent()
            .appendingPathComponent("module-audit-data", isDirectory: true).appendingPathComponent(name)
    }

    static func prepareIfRequested() {
        guard requested else { return }
        for module in PocketModule.allCases { UserDefaults.standard.set(false, forKey: module.availabilityKey) }
        UserDefaults.standard.removeObject(forKey: AwakeAutomationSettings.key)
        OnboardingRecord.markCompleted()
        // No screen capture, audio routing, clipboard reads or notifications are requested by this audit.
        UserDefaults.standard.set(false, forKey: PocketPreferenceKey.showWindowAtLaunch)
    }

    static func run(destination: URL) async {
        guard requested else { return }
        NSApp.appearance = NSAppearance(named: CommandLine.arguments.contains("--audit-dark") ? .darkAqua : .aqua)
        let awakeOnly = CommandLine.arguments.contains("--audit-awake-only")
        let permissionOnly = CommandLine.arguments.contains("--audit-permission-usage-only")
        if CommandLine.arguments.contains("--audit-update-sources-only") || awakeOnly || permissionOnly {
            let checks: [String: Bool]
            if permissionOnly { checks = await PermissionUsageRuntimeAudit.run(destination: destination) }
            else if awakeOnly { checks = await AwakeAutomationRuntimeAudit.run(destination: destination) }
            else { checks = await ApplicationUpdateRuntimeAudit.run(destination: destination) }
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            let report: [String: Any] = ["scope": permissionOnly ? "permission-usage" : (awakeOnly ? "awake-automation" : "application-update-sources"), "checks": checks,
                                         "passed": !checks.isEmpty && checks.values.allSatisfy { $0 },
                                         "sessionLocked": session?["CGSSessionScreenIsLocked"] as? Bool ?? false,
                                         "appearance": NSApp.effectiveAppearance.name.rawValue,
                                         "language": Bundle.main.preferredLocalizations.first ?? "unknown"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
            return
        }
        let runtime = PocketModuleRuntime.shared
        var checks: [String: Bool] = [:]
        var rows: [[String: Any]] = []
        checks["allOffLaunchCreatedNoServices"] = ModuleServiceProbe.created.isEmpty
        for cycle in 1...3 {
            for module in PocketModule.allCases { runtime.setAvailable(module, true) }
            try? await Task.sleep(for: .milliseconds(600))
            checks["cycle\(cycle)AllEnabled"] = runtime.available.count == PocketModule.allCases.count
            for module in PocketModule.allCases.reversed() { runtime.setAvailable(module, false) }
            try? await Task.sleep(for: .milliseconds(600))
            checks["cycle\(cycle)AllDisabled"] = runtime.available.isEmpty
            let resources = stoppedResources()
            checks["cycle\(cycle)ReleasedResources"] = resources.values.allSatisfy { $0.values.allSatisfy { $0 == 0 } }
            rows.append(["cycle": cycle, "resourcesAfterStop": resources])
        }
        checks["allServicesExercised"] = ModuleServiceProbe.created.count == 26
        checks.merge(await ShelfRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        checks.merge(await DockPreviewRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        checks.merge(await MixerRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        runtime.setAvailable(.commandBar, true)
        for source in ["applications", "windows", "clipboard", "snippets"] {
            UserDefaults.standard.set(false, forKey: "MacPocket.commandBar." + source)
        }
        let bar = CommandBarService.shared
        // Fixture windows can asynchronously change focus. A nonactivating panel needs key-window ownership,
        // not application activation. Record both; physical/global shortcut delivery is a separate acceptance test.
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let commandFocusPreparation: [String: Any] = ["activationPolicy": NSApp.activationPolicy().rawValue,
                                                      "appActive": NSApp.isActive,
                                                      "sessionLocked": session?["CGSSessionScreenIsLocked"] as? Bool ?? false]
        NSApp.activate(ignoringOtherApps: true)
        bar.show()
        _ = await waitUntil {
            guard let window = bar.diagnosticPanelWindow, let field = commandField(window.contentView) else { return false }
            return window.isKeyWindow && field.currentEditor() === window.firstResponder
        }
        checks["commandBarTestPaletteKey"] = bar.diagnosticPanelWindow?.isKeyWindow == true
        let commandResponder = bar.diagnosticPanelWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        if let window = bar.diagnosticPanelWindow {
            for (code, letter) in [(UInt16(38), "j"), (UInt16(1), "s"), (UInt16(31), "o"), (UInt16(45), "n")] {
                sendKeyNow(code, to: window, characters: letter)
            }
        }
        checks["commandBarSearchFocused"] = bar.query == "json"
        let typedQueryState = commandInputState(bar)
        bar.query = "ekran goruntusu"
        checks["commandBarBilingualSearch"] = bar.results.first?.id == "tool:screenshot"
        bar.query = "brightness 40"
        checks["commandBarParameter"] = bar.results.first?.id == "parameter"
        bar.query = ""
        if let palette = bar.diagnosticPanelWindow {
            snapshot(palette, to: destination.deletingPathExtension().appendingPathExtension("palette.png"))
        }
        let first = bar.selectedID
        var commandPhases: [[String: Any]] = []
        func noteCommandPhase(_ name: String) {
            commandPhases.append(["phase": name, "visible": bar.diagnosticPanelWindow?.isVisible == true,
                                  "key": bar.diagnosticPanelWindow?.isKeyWindow == true, "appActive": NSApp.isActive,
                                  "resultCount": bar.results.count, "resign": bar.diagnosticPanelResign ?? [:]])
        }
        noteCommandPhase("beforeDown")
        if let window = bar.diagnosticPanelWindow { sendKeyNow(125, to: window) }
        noteCommandPhase("afterDown")
        checks["commandBarDownArrow"] = first != bar.selectedID
        if let window = bar.diagnosticPanelWindow { sendKeyNow(126, to: window) }
        checks["commandBarUpArrow"] = first == bar.selectedID
        bar.query = "json"
        noteCommandPhase("jsonQuery")
        checks["commandBarFindsPracticalTool"] = bar.results.first?.id == "practical:json"
        let beforeEnterState = commandInputState(bar)
        if let window = bar.diagnosticPanelWindow { sendKeyNow(36, to: window) }
        let afterEnterState = commandInputState(bar)
        checks["commandBarEnterRoutesToTool"] = PocketApplicationState.shared.model.navigation.page == .practical && PracticalWorkspace.shared.selected == .json
        checks["commandBarEnterReleasesPanel"] = bar.moduleDiagnosticResources.values.allSatisfy { $0 == 0 } || bar.moduleDiagnosticResources.filter { $0.key != "shortcut" }.values.allSatisfy { $0 == 0 }
        bar.show()
        try? await Task.sleep(for: .milliseconds(100))
        bar.query = "no-such-macpocket-command-1234567"
        checks["commandBarEmptySearch"] = bar.results.isEmpty
        if let window = bar.diagnosticPanelWindow { await sendKey(53, to: window) }
        checks["commandBarEscapeClosesPanel"] = bar.moduleDiagnosticResources.filter { $0.key != "shortcut" }.values.allSatisfy { $0 == 0 }
        UserDefaults.standard.set(true, forKey: "MacPocket.commandBar.applications")
        UserDefaults.standard.set(true, forKey: "MacPocket.commandBar.windows")
        bar.show()
        let deadline = Date().addingTimeInterval(20)
        while bar.loading, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        bar.kind = .application
        checks["commandBarDiscoversApps"] = !bar.loading && !bar.results.isEmpty
        bar.kind = .window
        checks["commandBarDiscoversWindows"] = !bar.loading && !bar.results.isEmpty
        bar.close()
        runtime.setAvailable(.commandBar, false)
        // Run additional key-window fixtures after the palette keyboard checks; closing a titled window
        // can enqueue activation changes which correctly dismiss a nonactivating palette on resignKey.
        checks.merge(await MouseButtonRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        checks.merge(await ScreenshotRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        checks.merge(await ApplicationUpdateRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        checks.merge(await AwakeAutomationRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        checks.merge(await PermissionUsageRuntimeAudit.run(destination: destination), uniquingKeysWith: { _, new in new })
        // Render the real settings and disabled-tool surfaces with native controls in both languages.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        previewWindow = window
        window.title = String(localized: "Modüller")
        window.contentView = NSHostingView(rootView: PocketModuleSettings())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(500))
        checks["settingsHasNativeControls"] = countControls(window.contentView) > 10
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: destination.deletingPathExtension().appendingPathExtension("png"))
            }
        }
        let nodes = ToolUIAudit.accessibilityNodes(window)
        checks["settingsHasNamedToggles"] = nodes.filter { ["AXCheckBox", "AXSwitch"].contains($0["role"] ?? "") && !($0["name"] ?? "").isEmpty }.count >= 10
        window.selectNextKeyView(nil)
        checks["settingsKeyboardFocus"] = window.firstResponder is NSTextView || window.firstResponder is NSControl
        window.performClose(nil)
        try? await Task.sleep(for: .milliseconds(300))
        checks["previewWindowCloses"] = !window.isVisible
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        checks["previewWindowReopens"] = window.isVisible
        let report: [String: Any] = ["checks": checks, "cycles": rows, "createdServices": ModuleServiceProbe.created.sorted(),
                                     "language": Bundle.main.preferredLocalizations.first ?? "unknown", "appearance": window.effectiveAppearance.name.rawValue, "settingsControls": nodes, "windowNumber": window.windowNumber, "commandResponder": commandResponder,
                                     "passed": checks.values.allSatisfy { $0 }, "commandPhases": commandPhases,
                                     "typedQueryState": typedQueryState, "beforeEnterState": beforeEnterState, "afterEnterState": afterEnterState]
        var finalReport = report
        finalReport["commandFocusPreparation"] = commandFocusPreparation
        if let data = try? JSONSerialization.data(withJSONObject: finalReport, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: destination, options: .atomic)
        }
    }

    private static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    private static func sendKey(_ code: UInt16, to window: NSWindow, characters: String = "") async {
        sendKeyNow(code, to: window, characters: characters)
        try? await Task.sleep(for: .milliseconds(100))
    }
    /// Deliver the controlled key sequence in one main-actor turn after real field-editor readiness.
    /// NSApplication.sendEvent still exercises local monitors and the native responder chain.
    private static func sendKeyNow(_ code: UInt16, to window: NSWindow, characters: String = "") {
        let text: String
        if !characters.isEmpty { text = characters }
        else {
            switch code {
            case 125: text = "\u{F701}"
            case 126: text = "\u{F700}"
            case 36: text = "\r"
            case 53: text = "\u{1B}"
            default: text = ""
            }
        }
        let flags: NSEvent.ModifierFlags = (123...126).contains(code) ? [.function, .numericPad] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                                           isARepeat: false, keyCode: code) { NSApp.sendEvent(event) }
        }
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        repeat {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }
    private static func commandField(_ view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.accessibilityIdentifier() == "command.search" { return field }
        return view.subviews.lazy.compactMap { commandField($0) }.first
    }
    private static func commandInputState(_ bar: CommandBarService) -> [String: Any] {
        let window = bar.diagnosticPanelWindow, field = commandField(window?.contentView)
        let editor = field?.currentEditor() as? NSTextView
        return ["queryLength": bar.query.count, "fieldLength": field?.stringValue.count ?? -1,
                "editorLength": editor?.string.count ?? -1, "editorMarkedText": editor?.hasMarkedText() == true,
                "fieldMatchesQuery": field?.stringValue == bar.query, "keyWindow": window?.isKeyWindow == true,
                "fieldEditorFocused": editor != nil && editor === window?.firstResponder,
                "selectedPracticalJSON": bar.selectedID == "practical:json"]
    }

    private static func countControls(_ root: NSView?) -> Int {
        guard let root else { return 0 }
        return (root is NSControl ? 1 : 0) + root.subviews.reduce(0) { $0 + countControls($1) }
    }

    private static func stoppedResources() -> [String: [String: Int]] {
        [
            "sharedHotKeys": PocketGlobalHotKey.diagnosticResources,
            "commandBar": CommandBarService.shared.moduleDiagnosticResources,
            "shelf": ShelfService.shared.moduleDiagnosticResources,
            "dockPreview": DockPreviewService.shared.moduleDiagnosticResources,
            "windowSwitcher": WindowSwitcherHotkeyController.shared.moduleDiagnosticResources,
            "windowLayout": WindowLayoutService.shared.moduleDiagnosticResources,
            "clipboard": ClipboardService.shared.moduleDiagnosticResources,
            "quitGuard": QuitGuardService.shared.moduleDiagnosticResources,
            "brightness": DisplayBrightnessService.shared.moduleDiagnosticResources,
            "night": NightModeService.shared.moduleDiagnosticResources,
            "displaySettings": DisplaySettingsService.shared.moduleDiagnosticResources,
            "monitorVolume": MonitorVolumeService.shared.moduleDiagnosticResources,
            "macros": MacroService.shared.moduleDiagnosticResources,
            "freezer": AppFreezerService.shared.moduleDiagnosticResources,
            "focus": FocusSessionService.shared.moduleDiagnosticResources,
            "workspaces": WorkspaceService.shared.moduleDiagnosticResources,
            "snippets": SnippetService.shared.moduleDiagnosticResources,
            "screenGrab": ScreenGrabService.shared.moduleDiagnosticResources,
            "screenshot": ScreenshotService.shared.moduleDiagnosticResources,
            "bluetooth": BluetoothBatteryService.shared.moduleDiagnosticResources,
            "screenTime": ScreenTimeService.shared.moduleDiagnosticResources,
            "mouseButtons": MouseButtonService.shared.moduleDiagnosticResources,
            "mouse": MouseScrollService.shared.moduleDiagnosticResources,
            "audioOutput": AudioOutputService.shared.moduleDiagnosticResources,
            "mixer": VolumeMixerService.shared.moduleDiagnosticResources,
            "recorder": ScreenRecorderService.shared.moduleDiagnosticResources,
            "privacy": PrivacyMonitorService.shared.moduleDiagnosticResources
        ]
    }
}
#endif
