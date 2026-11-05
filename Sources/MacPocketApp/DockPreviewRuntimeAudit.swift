#if DEBUG
import AppKit
import MacPocketCore
import SwiftUI

@MainActor
enum DockPreviewRuntimeAudit {
    private static var settingsWindow: NSWindow?
    static func run(destination: URL) async -> [String: Bool] {
        guard ModuleRuntimeAudit.requested, let screen = NSScreen.main else { return [:] }
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(200))
        let runtime = PocketModuleRuntime.shared
        runtime.setAvailable(.dockPreview, true)
        let service = DockPreviewService.shared
        var checks: [String: Bool] = [:]
        service.settings.enabled = false
        checks["dockDisabledHasNoMouseMonitors"] = service.moduleDiagnosticResources["globalMonitor"] == 0 && service.moduleDiagnosticResources["localMonitor"] == 0
        service.settings.enabled = true
        checks["dockPermissionControlsMonitoring"] = service.trusted
            ? service.moduleDiagnosticResources["globalMonitor"] == 1 && service.moduleDiagnosticResources["localMonitor"] == 1
            : service.moduleDiagnosticResources["globalMonitor"] == 0 && service.moduleDiagnosticResources["localMonitor"] == 0
        service.settings.enabled = false
        // Keep the synthetic icon inside its intended display even when that display has no Dock inset.
        let frame = CGRect(x: screen.frame.midX - 28, y: screen.frame.minY + 4, width: 56, height: 56)
        checks.merge(await liveApplicationChecks(service: service, anchor: frame, destination: destination), uniquingKeysWith: { _, new in new })
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(250))
        let item = DockHoverItem(applicationURL: Bundle.main.bundleURL, application: "MacPocket Fixture", processIDs: [getpid()], iconFrame: frame)
        var rows: [SwitchableWindow] = []
        for index in 0..<9 {
            let title = index == 0 ? "Uzun belge başlığı — A document with a long title and Unicode 👋" : "Document \(index + 1)"
            var row = SwitchableWindow(id: "dock-fixture-\(index)", processID: getpid(), application: "MacPocket Fixture", title: title,
                             applicationURL: Bundle.main.bundleURL, minimized: index == 1, hidden: index == 2,
                             fullScreen: false, frontmost: index == 0, windowAccessible: true, canClose: true,
                             canMinimize: true, canFullScreen: true, launchedAt: nil, lastFocusedAt: nil)
            row.windowID = UInt32(index + 1)
            row.otherSpace = index == 3
            row.canResize = true
            rows.append(row)
        }
        let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: rows.filter { !$0.minimized }.map { ($0.id, fixtureImage()) })
        service.diagnosticShow(item, windows: rows, images: images)
        try? await Task.sleep(for: .milliseconds(350))
        if let panel = service.diagnosticWindow {
            checks["dockPanelFitsScreen"] = screen.visibleFrame.contains(panel.frame)
            let geometry: [String: Any] = ["anchor": NSStringFromRect(frame), "panel": NSStringFromRect(panel.frame),
                "intendedScreen": NSStringFromRect(screen.frame), "visibleFrame": NSStringFromRect(screen.visibleFrame),
                "screens": NSScreen.screens.map { NSStringFromRect($0.frame) }]
            if let data = try? JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination.appendingPathExtension("dock-geometry.json"))
            }
            let nodes = ToolUIAudit.accessibilityNodes(panel)
            checks["dockHasAccessibleWindowActions"] = nodes.contains { $0["name"] == String(localized: "Pencereyi kapat") }
            snapshot(panel, to: destination.appendingPathExtension("dock.png"))
            service.selectedID = rows[0].id
            let first = service.selectedID
            checks["dockGridOwnsKeyboardFocus"] = service.diagnosticKeyboardState["gridFirstResponder"] == true
            if let data = try? JSONSerialization.data(withJSONObject: service.diagnosticKeyboardState, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination.appendingPathExtension("dock-keyboard.json"))
            }
            await sendKey(124, to: panel)
            checks["dockRightArrowSelectsNext"] = service.selectedID != first && service.selectedID == rows[1].id
            await sendKey(123, to: panel)
            checks["dockLeftArrowSelectsPrevious"] = service.selectedID == first
            await sendKey(125, to: panel)
            checks["dockDownArrowSelectsNextRow"] = service.selectedID == rows[3].id
            await sendKey(126, to: panel)
            checks["dockUpArrowSelectsPreviousRow"] = service.selectedID == first
            // Fixture IDs cannot be present in the real catalog: safe error-path validation, never a foreign window mutation.
            service.perform(.focus, on: rows[0])
            try? await Task.sleep(for: .milliseconds(250))
            checks["dockStaleWindowShowsFailure"] = service.message != nil && service.actionBusyID == nil
            if let data = try? JSONSerialization.data(withJSONObject: ["state": service.diagnosticKeyboardState,
                                                                       "ignoredFixtureEvents": service.diagnosticIgnoredEvents], options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination.appendingPathExtension("dock-keyboard.json"))
            }
            await sendKey(53, to: panel)
            checks["dockEscapeClosesAndDropsImages"] = !panel.isVisible && service.thumbnails.isEmpty
        } else { checks["dockPanelCreated"] = false }
        service.diagnosticShow(item, windows: [])
        try? await Task.sleep(for: .milliseconds(200))
        if let panel = service.diagnosticWindow { snapshot(panel, to: destination.appendingPathExtension("dock-empty.png")) }
        checks["dockEmptyStateStillDismisses"] = service.diagnosticWindow?.isVisible == true && service.windows.isEmpty
        service.close()
        let unrelated = DockHoverItem(applicationURL: item.applicationURL, application: item.application, processIDs: [-1], iconFrame: frame)
        service.diagnosticShow(unrelated, windows: rows)
        service.handleWorkspaceChange(NSWorkspace.didTerminateApplicationNotification, processID: getpid(), bundleID: Bundle.main.bundleIdentifier)
        checks["dockUnrelatedAppExitKeepsPanel"] = service.diagnosticWindow?.isVisible == true
        service.handleWorkspaceChange(NSWorkspace.didActivateApplicationNotification, processID: getpid(), bundleID: Bundle.main.bundleIdentifier)
        checks["dockOwnActivationKeepsPanel"] = service.diagnosticWindow?.isVisible == true
        service.diagnosticShow(item, windows: rows)
        service.handleWorkspaceChange(NSWorkspace.didTerminateApplicationNotification, processID: getpid(), bundleID: Bundle.main.bundleIdentifier)
        checks["dockTargetExitClosesPanel"] = service.diagnosticWindow?.isVisible == false
        rows = Array(rows.prefix(1))
        service.diagnosticShow(item, windows: rows, images: images)
        service.excludeTarget()
        checks["dockExclusionClosesPanel"] = service.settings.excludedPaths.contains(item.applicationURL.path) && service.diagnosticWindow?.isVisible == false
        service.settings.excludedPaths = []
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        settingsWindow.isReleasedWhenClosed = false
        Self.settingsWindow = settingsWindow
        settingsWindow.contentView = NSHostingView(rootView: DockPreviewSettingsView().pocketAppearanceRoot())
        settingsWindow.center(); settingsWindow.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(350))
        let settingsNodes = ToolUIAudit.accessibilityNodes(settingsWindow)
        if let data = try? JSONSerialization.data(withJSONObject: settingsNodes, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination.appendingPathExtension("dock-settings.ax.json"))
        }
        checks["dockSettingsHasEnableControl"] = settingsNodes.contains { $0["name"] == String(localized: "Dock pencere önizlemelerini aç") }
        checks["dockSettingsHasPermissionRefresh"] = settingsNodes.contains { $0["name"] == String(localized: "İzin Durumunu Yenile") }
        snapshot(settingsWindow, to: destination.appendingPathExtension("dock-settings.png"))
        settingsWindow.orderOut(nil)
        settingsWindow.contentView = nil
        service.diagnosticShow(item, windows: rows)
        runtime.setAvailable(.dockPreview, false)
        checks["dockModuleStopsEveryResource"] = service.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        return checks
    }

    private static func fixtureImage() -> NSImage {
        NSImage(size: NSSize(width: 420, height: 240), flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill(); rect.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            NSRect(x: 14, y: 180, width: 392, height: 42).fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            for row in 0..<5 { NSRect(x: 24, y: 150 - CGFloat(row) * 24, width: 330 - CGFloat(row) * 22, height: 8).fill() }
            return true
        }
    }

    private static func liveApplicationChecks(service: DockPreviewService, anchor: CGRect, destination: URL) async -> [String: Bool] {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("MacPocketDockFixture.app")
        guard Bundle(url: url)?.bundleIdentifier == "com.doancan.MacPocket.DockFixture" else { return ["dockLiveFixtureAvailable": false] }
        let pid: Int32? = await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                continuation.resume(returning: error == nil ? app?.processIdentifier : nil)
            }
        }
        guard let pid, let app = NSRunningApplication(processIdentifier: pid),
              app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath(),
              app.bundleIdentifier == "com.doancan.MacPocket.DockFixture" else { return ["dockLiveFixtureLaunch": false] }
        defer {
            // Only the exact disposable app returned by the launch above can be terminated.
            if !app.isTerminated { app.terminate() }
        }
        let launchDeadline = Date().addingTimeInterval(3)
        while !app.isFinishedLaunching, Date() < launchDeadline { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(200))
        let item = DockHoverItem(applicationURL: url, application: "MacPocket Dock Fixture", processIDs: [pid], iconFrame: anchor)
        service.show(item, focus: false)
        let deadline = Date().addingTimeInterval(6)
        while (service.loading || service.windows.count < 2), Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        let discovered = service.windows.count >= 2 && service.windows.allSatisfy { $0.processID == pid && $0.windowID != nil }
        let visible = service.diagnosticWindow?.isVisible == true
        if let window = service.diagnosticWindow { snapshot(window, to: destination.appendingPathExtension("dock-live.png")) }
        let requested = app.terminate()
        let exitDeadline = Date().addingTimeInterval(5)
        while (!app.isTerminated || service.diagnosticWindow?.isVisible == true), Date() < exitDeadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let stopped = app.isTerminated
        let dismissed = service.diagnosticWindow?.isVisible == false
        if !stopped { app.forceTerminate() }
        service.close()
        return ["dockLiveFixtureLaunch": true, "dockLiveWindowCatalogue": discovered,
                "dockLivePanelVisibleBeforeExit": visible, "dockLiveFixtureTerminates": requested && stopped,
                "dockLiveTargetExitClosesPanel": visible && dismissed]
    }
    private static func sendKey(_ code: UInt16, to window: NSWindow) async {
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, characters: code == 53 ? "\u{1B}" : "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) {
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
    private static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}
#endif
