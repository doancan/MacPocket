#if DEBUG
import AppKit
import Darwin
import MacPocketCore
import SwiftUI

@MainActor
enum WindowSwitcherPermissionProbe {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--probe-switcher-permissions") else { return }
        guard arguments.indices.contains(index + 1) else { exit(2) }
        let report: [String: Any] = ["bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
                                   "accessibilityGranted": AXIsProcessTrusted(), "screenCaptureGranted": WindowPreviewProvider.permitted,
                                   "source": "read-only-preflight-before-app-state", "applicationStateStarted": false]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
        }
    }
}

/// Renders the real switcher in a separate bundle using owned fixture images. Reports distinguish
/// local AppKit input and fixture captures from physical hotkeys, AX actions and ScreenCaptureKit.
@MainActor
enum WindowSwitcherRuntimeAudit {
    private static var syntheticFocusRestorations = 0

    static var requested: Bool {
        CommandLine.arguments.contains("--audit-switcher") && Bundle.main.bundleIdentifier?.hasSuffix(".SwitcherAudit") == true
    }

    static func prepareIfRequested() {
        guard requested else { return }
        for module in PocketModule.allCases { UserDefaults.standard.set(false, forKey: module.availabilityKey) }
        UserDefaults.standard.set(false, forKey: PocketPreferenceKey.showWindowAtLaunch)
        UserDefaults.standard.set(true, forKey: PocketPreferenceKey.showInDock)
        UserDefaults.standard.set(false, forKey: "switcher.hoverSelects")
        OnboardingRecord.markCompleted()
    }

    static func run(destination: URL) async {
        guard requested else { return }
        var checks: [String: Bool] = [:]
        var variants: [[String: Any]] = []
        var settingsVariants: [[String: Any]] = []
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if CommandLine.arguments.contains("--only-tabs") {
                let tabs = await WindowTabsRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
                let report: [String: Any] = ["checks": checks, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "ownedNativeTabs": tabs]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
                NSApp.terminate(nil); return
            }
            if CommandLine.arguments.contains("--only-lifecycle") {
                let lifecycle = try await WindowLifecycleRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
                let report: [String: Any] = ["checks": checks, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "ownedLifecycle": lifecycle]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
                NSApp.terminate(nil); return
            }
            // Synthetic local input needs the audit application to finish activation. This does not
            // stand in for the production switcher's nonactivating, physical-keyboard acceptance.
            // A regular owned window gives AppKit a stable activation target between HUD sessions.
            NSApp.setActivationPolicy(.regular)
            let activationAnchor = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 160, height: 80),
                                            styleMask: [.titled], backing: .buffered, defer: false)
            activationAnchor.isReleasedWhenClosed = false
            activationAnchor.title = "MacPocket Switcher Audit"
            activationAnchor.makeKeyAndOrderFront(nil)
            defer { activationAnchor.orderOut(nil) }
            NSApp.activate(ignoringOtherApps: true)
            let activationDeadline = Date().addingTimeInterval(3)
            while !NSApp.isActive, Date() < activationDeadline { try? await Task.sleep(for: .milliseconds(30)) }
            try? await Task.sleep(for: .milliseconds(250))
            if CommandLine.arguments.contains("--only-settings") {
                let evidence = await auditSettingsForm(shortcuts: [.defaultOptionTab], destination: destination, checks: &checks)
                let report: [String: Any] = ["checks": checks, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "settings": evidence,
                    "physicalKeyboardVerified": false, "source": "owned-SwiftUI-settings-and-native-accessibility-actions"]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-hold") {
                let evidence = try await SwitcherHoldRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
                let report: [String:Any] = ["checks": checks,"passed": !checks.isEmpty && checks.values.allSatisfy { $0 },"holdSettings": evidence,"input": "local-AppKit-events-and-injected-modifier-state","focus": "owned-catalog-fixture","physicalKeyboardVerified": false,"globalCommandTabExercised": false]
                try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: destination,options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-cli") {
                try await SwitcherCLIRuntimeAudit.run(checks: &checks)
                let report: [String:Any] = ["checks": checks,"passed": !checks.isEmpty && checks.values.allSatisfy { $0 },"transport": "native-CFMessagePort","panel": "production-AppKit","focus": "owned-catalog-fixture","physicalKeyboardVerified": false,"thirdPartyFocusVerified": false]
                try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: destination,options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-transfer") {
                let transfer = await SwitcherTransferRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
                let report: [String: Any] = ["checks": checks,"passed": !checks.isEmpty && checks.values.allSatisfy { $0 },"transfer": transfer,"realSettingsFilePanelsVerified": SwitcherTransferRuntimeAudit.filePanelsVerified(checks)]
                try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: destination,options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-badges") {
                let badges = await SwitcherBadgeRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
                let report: [String: Any] = ["checks": checks,"passed": !checks.isEmpty && checks.values.allSatisfy { $0 },"badges": badges,"realDockTransportVerified": false]
                try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: destination,options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-gesture") {
                let gestures = await SwitcherGestureRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
                let report: [String: Any] = ["checks": checks,"passed": !checks.isEmpty && checks.values.allSatisfy { $0 },"gestures": gestures,
                                           "physicalGesturesVerified": false,"hapticHardwareVerified": false,"inputSource": "copied-contact-fixtures-through-production-relay"]
                try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: destination,options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-navigation") {
                let navigation = try await SwitcherNavigationRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
                let report: [String: Any] = ["checks": checks,"passed": !checks.isEmpty && checks.values.allSatisfy { $0 },"navigation": navigation,
                                           "physicalHotkeysVerified": false,"inputSource": "local-AppKit-events"]
                try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: destination,options: .atomic)
                NSApp.terminate(nil);return
            }
            if CommandLine.arguments.contains("--only-appearance") {
                let appearance = try await SwitcherAppearanceRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
                let report: [String: Any] = ["checks": checks, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 }, "appearanceOptions": appearance]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
                NSApp.terminate(nil); return
            }
            let fixture = try AuditCapture()
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                NSApp.appearance = NSAppearance(named: appearance)
                for style in SwitcherStyle.allCases {
                    UserDefaults.standard.set(style.rawValue, forKey: "switcher.style")
                    for solid in [false, true] {
                        UserDefaults.standard.set(solid, forKey: PocketPreferenceKey.reduceMotion)
                        let model = WindowSwitcherModel(windows: fixtureWindows(), previews: fixture, permitsCapture: { true })
                        let controller = WindowSwitcherHotkeyController(model: model)
                        model.selection = "fixture-0"
                        guard let panel = controller.beginVisualAudit(reduceTransparency: solid) else { continue }
                        try? await Task.sleep(for: .milliseconds(350))
                        let prefix = "\(appearance.rawValue)-\(style.rawValue)-\(solid ? "solid-reduced-motion" : "glass")"
                        checks[prefix + "Visible"] = panel.isVisible
                        checks[prefix + "Key"] = panel.isKeyWindow
                        checks[prefix + "CapturesOnlyThumbnailStyle"] = style == .thumbnails ? !model.thumbnails.isEmpty : model.thumbnails.isEmpty
                        checks[prefix + "AppActiveForLocalInput"] = NSApp.isActive
                        await sendKey(48, to: panel)
                        try? await Task.sleep(for: .milliseconds(220))
                        checks[prefix + "Tab"] = model.selection == "fixture-1"
                        await sendKey(48, to: panel, modifiers: .shift)
                        checks[prefix + "ShiftTab"] = model.selection == "fixture-0"
                        await sendKey(0, to: panel, characters: "a")
                        try? await Task.sleep(for: .milliseconds(60))
                        checks[prefix + "Search"] = model.sessionSearch == "a"
                        await sendKey(53, to: panel)
                        checks[prefix + "EscapeClearsSearch"] = model.sessionSearch.isEmpty && panel.isVisible
                        model.selection = "fixture-1"
                        try? await Task.sleep(for: .milliseconds(200))
                        panel.contentView?.layoutSubtreeIfNeeded()
                        let snapshotURL = destination.deletingLastPathComponent().appendingPathComponent(prefix + ".png")
                        checks[prefix + "Snapshot"] = snapshot(panel, to: snapshotURL)
                        variants.append(["style": style.rawValue, "appearance": appearance.rawValue, "reduceTransparency": solid, "reduceMotion": solid,
                                         "frame": NSStringFromRect(panel.frame), "thumbnails": model.thumbnails.count,
                                         "snapshot": snapshotURL.lastPathComponent,
                                         "accessibility": ToolUIAudit.accessibilityNodes(panel)])
                        await sendKey(53, to: panel)
                        checks[prefix + "EscapeCloses"] = !panel.isVisible
                        controller.stopForModule()
                    }
                }
            }
            // Exercise the actual session/controller paths with a fake catalog. No AX mutation
            // or external window activation occurs; only the routing and local UI are accepted here.
            let catalog = AuditCatalog(windows: fixtureWindows())
            UserDefaults.standard.set(SwitcherStyle.thumbnails.rawValue, forKey: "switcher.style")
            UserDefaults.standard.set(SwitcherTheme.system.rawValue, forKey: "switcher.theme")
            UserDefaults.standard.set(WindowSortOrder.recent.rawValue, forKey: "switcher.sort")
            var first = SwitcherShortcut.defaultOptionTab
            first.presentation.style = .titles; first.presentation.theme = .dark
            first.presentation.sizeScale = 0.8; first.presentation.autoSize = false
            first.presentation.order = .title; first.presentation.previewSelected = true
            var second = SwitcherShortcut(keyCode: SwitcherKeys.grave, modifiers: .option, releaseBehavior: .search)
            second.presentation.style = .icons; second.presentation.theme = .light
            second.filter.currentApplicationOnly = true
            let model = WindowSwitcherModel(windows: fixtureWindows(), catalog: catalog, previews: fixture, permitsCapture: { true })
            let controller = WindowSwitcherHotkeyController(model: model, foregroundApplication: { NSRunningApplication.current })
            _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: first)
            checks["presetResolvesStyleSizeAndPreview"] = controller.style == .titles && controller.activePresentation?.sizeScale == 0.8
                && controller.activePresentation?.previewSelected == true && controller.activePresentation?.autoSize == false
            checks["presetDarkTheme"] = controller.auditPanel?.appearance?.name == .darkAqua
            checks["presetTitleOrder"] = model.filtered.map(\.title) == model.filtered.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            controller.show(shortcut: second)
            _ = await waitUntil { !model.busy && controller.auditPanel?.isVisible == true }
            checks["differentPresetChangesScopeAndStyle"] = controller.activeShortcut?.id == second.id && controller.style == .icons && model.filtered.count == 2
            checks["presetLightTheme"] = controller.auditPanel?.appearance?.name == .aqua
            checks["unsetPresetScaleUsesGlobal"] = controller.activePresentation?.sizeScale == SwitcherPresentation.load().sizeScale
            let beforeStep = model.selection
            controller.show(shortcut: second)
            checks["samePresetCycles"] = model.selection != beforeStep
            controller.releaseModifiersForAudit()
            checks["releaseEntersEmptySearch"] = model.isSearching && model.sessionSearch.isEmpty && controller.auditPanel?.isVisible == true
            if let panel = controller.auditPanel {
                await sendKey(0, to: panel, characters: "a"); await sendKey(51, to: panel)
            }
            controller.releaseModifiersForAudit()
            let noFocusAfterSearch = await catalog.focused.isEmpty
            checks["emptySearchDoesNotCommitOnRelease"] = model.isSearching && model.sessionSearch.isEmpty && noFocusAfterSearch
            var revisedPreset = second
            revisedPreset.presentation.titleMode = .application
            controller.show(shortcut: revisedPreset)
            _ = await waitUntil { !model.busy && controller.auditPanel?.isVisible == true }
            checks["samePresetWithChangedOptionsStartsFreshPresentation"] = controller.presentation.titleMode == .application && !model.isSearching
            var hold = SwitcherShortcut(keyCode: SwitcherKeys.space, modifiers: .control, releaseBehavior: .hold)
            hold.presentation.style = .thumbnails
            controller.show(shortcut: hold)
            _ = await waitUntil { !model.busy }
            controller.releaseModifiersForAudit()
            let noFocusAfterHold = await catalog.focused.isEmpty
            checks["holdDoesNotCommit"] = controller.auditPanel?.isVisible == true && noFocusAfterHold
            var bindings = SwitcherActionBinding.defaults
            if let index = bindings.firstIndex(where: { $0.action == .close }) { bindings[index].keyCode = 2 }
            controller.saveActionBindings(bindings)
            if let panel = controller.auditPanel { await sendKey(13, to: panel, characters: "w", modifiers: .command) }
            try? await Task.sleep(for: .milliseconds(40))
            let noOldAction = await catalog.actions.isEmpty
            checks["oldActionBindingIsInactive"] = noOldAction
            if let panel = controller.auditPanel { await sendKey(2, to: panel, characters: "d", modifiers: .command) }
            checks["customActionRoutesToCatalog"] = await waitUntil { await catalog.actions.contains("close") }
            _ = await waitUntil { !model.actionBusy }
            controller.show(shortcut: first)
            _ = await waitUntil { !model.busy }
            let chosen = model.selection
            controller.releaseModifiersForAudit()
            checks["chooseReleaseRoutesSelectedIdentity"] = await waitUntil { await catalog.focused == chosen.map { [$0] } ?? [] }
            checks["chooseReleaseClosesPanel"] = controller.auditPanel?.isVisible != true
            controller.stopForModule()
            controller.saveActionBindings(SwitcherActionBinding.defaults)

            var scoped = SwitcherShortcut(keyCode: SwitcherKeys.grave, modifiers: .option, releaseBehavior: .hold)
            scoped.filter.applicationScope = .other
            scoped.presentation.style = .titles
            _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: scoped)
            model.foregroundPID = ProcessInfo.processInfo.processIdentifier
            checks["inactiveApplicationScope"] = model.filtered.map(\.id) == ["fixture-2"]
            model.selection = "fixture-2"
            if let panel = controller.auditPanel { await sendKey(48, to: panel) }
            checks["scopedTabKeepsEligibleWindow"] = model.selection == "fixture-2"
            scoped.filter.applicationScope = .all; scoped.filter.grouping = .onePerApplication
            scoped.id = UUID()
            controller.show(shortcut: scoped)
            _ = await waitUntil { !model.busy }
            checks["applicationGroupingInActualPanel"] = model.filtered.count == 2 && Set(model.filtered.map(\.processID)).count == 2
            model.sessionSearch = "Haftalık"
            checks["searchSelectsEligibleGroupedWindow"] = model.filtered.map(\.id) == ["fixture-1"]
            controller.stopForModule()

            var spaceWindows = fixtureWindows()
            spaceWindows[0].spaceMembership = .init(spaces: [.init(id: 12, ordinal: 2, displayIdentifier: "Fixture", kind: .desktop, visible: false)])
            spaceWindows[1].spaceMembership = .init(spaces: [.init(id: 11, ordinal: 1, displayIdentifier: "Fixture", kind: .desktop, visible: true)])
            let spaceModel = WindowSwitcherModel(windows: spaceWindows, catalog: AuditCatalog(windows: spaceWindows), previews: fixture, permitsCapture: { true })
            let spaceController = WindowSwitcherHotkeyController(model: spaceModel)
            var spaceShortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab, modifiers: .option, releaseBehavior: .hold)
            spaceShortcut.presentation.style = .titles; spaceShortcut.presentation.order = .space
            spaceModel.selection = "fixture-1"
            if let panel = spaceController.beginVisualAudit(reduceTransparency: true, shortcut: spaceShortcut) {
                try? await Task.sleep(for: .milliseconds(180))
                checks["fixturePanelUsesSpaceOrder"] = spaceModel.filtered.map(\.id) == ["fixture-1", "fixture-0", "fixture-2"]
                let values = accessibilityValues(panel).joined(separator: " ")
                checks["fixtureSpaceNamesAreAccessibleAndLocalized"] = values.contains(spaceWindows[1].spaceMembership!.localizedDescription)
                    && values.contains(spaceWindows[0].spaceMembership!.localizedDescription)
                await sendKey(48, to: panel)
                checks["fixtureSpaceOrderControlsTabNavigation"] = spaceModel.selection == "fixture-0"
                let url = destination.deletingLastPathComponent().appendingPathComponent("space-order-panel.png")
                checks["fixtureSpaceOrderPanelSnapshot"] = snapshot(panel, to: url)
                variants.append(["kind": "space-membership-fixture", "style": "titles", "snapshot": url.lastPathComponent,
                                 "accessibilityValues": values, "membershipSource": "owned-fixture-data"])
                spaceShortcut.id = UUID(); spaceShortcut.filter.spaceScope = .notVisible
                spaceController.show(shortcut: spaceShortcut)
                _ = await waitUntil { !spaceModel.busy }
                try? await Task.sleep(for: .milliseconds(180))
                checks["fixtureSpaceFilterPrefersMembership"] = spaceModel.filtered.map(\.id) == ["fixture-0", "fixture-2"]
                let filteredValues = accessibilityValues(panel).joined(separator: " ")
                checks["fixtureSpaceFilterRendersEligibleWindows"] = filteredValues.contains(spaceWindows[0].title)
                    && filteredValues.contains(spaceWindows[2].title) && !filteredValues.contains(spaceWindows[1].title)
                let filteredURL = destination.deletingLastPathComponent().appendingPathComponent("space-filter-panel.png")
                checks["fixtureSpaceFilterPanelSnapshot"] = snapshot(panel, to: filteredURL)
                variants.append(["kind": "space-filter-fixture", "style": "titles", "snapshot": filteredURL.lastPathComponent,
                                 "accessibilityValues": filteredValues, "membershipSource": "owned-fixture-data"])
            }
            spaceController.stopForModule()

            var filter = WindowListFilter()
            filter.applicationScope = .pointerApplication; filter.spaceScope = .notVisible
            filter.minimized = .atEnd; filter.hidden = .hide; filter.windowless = .atEnd
            filter.includeFullScreen = false; filter.grouping = .onePerApplication
            NSApp.appearance = NSAppearance(named: .aqua)
            for width in [520.0, 760.0] {
                let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: width, height: 620),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = NSHostingView(rootView: FilterOptionsAuditView(filter: filter).preferredColorScheme(.light)
                    .background(Color(nsColor: .windowBackgroundColor)))
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(200))
                let nodes = ToolUIAudit.accessibilityNodes(window)
                let popups = nodes.filter { $0["role"] == "AXPopUpButton" }
                checks["filters\(Int(width))ContainsNativePickers"] = popups.count == 7
                let values = accessibilityValues(window)
                let text = values.joined(separator: " ")
                checks["filters\(Int(width))ShowsSelectedPolicies"] = text.contains(WindowVisibilityPolicy.atEnd.localizedTitle)
                    && text.contains(WindowGrouping.onePerApplication.localizedTitle) && text.contains(WindowApplicationScope.pointerApplication.localizedTitle)
                let overflow = nodes.filter { node in
                    guard let x = Double(node["x"] ?? ""), let controlWidth = Double(node["width"] ?? ""), controlWidth > 0 else { return false }
                    return x < window.frame.minX - 2 || x + controlWidth > window.frame.maxX + 2
                }
                checks["filters\(Int(width))NoMeasuredHorizontalOverflow"] = overflow.isEmpty
                let url = destination.deletingLastPathComponent().appendingPathComponent("filter-options-\(Int(width)).png")
                checks["filters\(Int(width))Snapshot"] = snapshot(window, to: url)
                settingsVariants.append(["width": width, "kind": "filters", "accessibility": nodes, "values": values,
                                         "horizontalOverflowHeuristic": overflow, "snapshot": url.lastPathComponent])
                window.orderOut(nil)
            }

            // Real native form controls, including long English labels, at two widths.
            for width in [520.0, 760.0] {
                let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: width, height: 480),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: ShortcutOptionsAuditView(shortcut: first))
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(200))
                let nodes = ToolUIAudit.accessibilityNodes(window)
                let popups = nodes.filter { $0["role"] == "AXPopUpButton" }
                checks["options\(Int(width))ContainsNativePickers"] = popups.count >= 6
                let url = destination.deletingLastPathComponent().appendingPathComponent("shortcut-options-\(Int(width)).png")
                checks["options\(Int(width))Snapshot"] = snapshot(window, to: url)
                settingsVariants.append(["width": width, "accessibility": nodes, "snapshot": url.lastPathComponent])
                window.orderOut(nil)
            }
            settingsVariants += await auditSettingsForm(shortcuts: [first, second], destination: destination, checks: &checks)
            await auditEnvironmentRefresh(fixture: fixture, checks: &checks)
            await auditConcurrentCatalogSnapshots(checks: &checks)
            let transferEvidence = await SwitcherTransferRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
            let badgeEvidence = await SwitcherBadgeRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
            let gestureEvidence = await SwitcherGestureRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
            let cursorEvidence = await SwitcherCursorRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
            let navigationEvidence = try await SwitcherNavigationRuntimeAudit.run(destination: destination.deletingLastPathComponent(),checks: &checks)
            let exceptionEvidence = await SwitcherExceptionsRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
            let appearanceEvidence = try await SwitcherAppearanceRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
            let spaceEvidence = await auditOwnedSpaceMetadata(anchorID: UInt32(activationAnchor.windowNumber), checks: &checks)
            let tabEvidence = await WindowTabsRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
            let lifecycleEvidence = try await WindowLifecycleRuntimeAudit.run(destination: destination.deletingLastPathComponent(), checks: &checks)
            // The audit itself is frontmost, and self-observation is excluded. This accepts the
            // shared lifecycle without reading or observing another application's AX windows.
            activationAnchor.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            _ = await waitUntil { NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() }
            checks["focusLeaseAuditOwnApplicationIsFrontmost"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
            let firstLease = WindowFocusObservation(), secondLease = WindowFocusObservation()
            firstLease.start(); secondLease.start(); firstLease.start()
            checks["focusLeasesShareOneWorkspaceSubscription"] = WindowFocusObservation.diagnosticResources["owners"] == 2
                && WindowFocusObservation.diagnosticResources["workspaceObservers"] == 2
            checks["focusAuditDoesNotObserveExternalWindows"] = WindowFocusObservation.diagnosticResources["axObservers"] == 0
                && WindowFocusObservation.diagnosticResources["readTasks"] == 0
            firstLease.stop()
            checks["oneLeaseStoppingKeepsOtherAlive"] = WindowFocusObservation.diagnosticResources["owners"] == 1
                && WindowFocusObservation.diagnosticResources["workspaceObservers"] == 2
            secondLease.stop()
            checks["lastFocusLeaseReleasesAllResources"] = WindowFocusObservation.diagnosticResources.values.allSatisfy { $0 == 0 }
            let report: [String: Any] = ["checks": checks, "passed": !checks.isEmpty && checks.values.allSatisfy { $0 },
                                         "variants": variants, "settingsVariants": settingsVariants, "exceptionVariants": exceptionEvidence,"transfer": transferEvidence,"realSettingsFilePanelsVerified": SwitcherTransferRuntimeAudit.filePanelsVerified(checks),"badges": badgeEvidence,"realDockTransportVerified": false,"gestures": gestureEvidence,"physicalGesturesVerified": false,"hapticHardwareVerified": false,"navigation": navigationEvidence,"cursor": cursorEvidence, "captureSource": "owned-fixture-images",
                                         "catalogSource": "owned-fixture-catalog",
                                         "inputSource": "local-AppKit-events", "physicalHotkeysVerified": false,
                                         "sessionContextSource": "owned-running-application-fixture",
                                         "syntheticWindowFocusControlled": true, "syntheticFocusRestorations": syntheticFocusRestorations,
                                         "hoverInputVerified": false, "externalClickDismissalVerified": false,
                                         "realWindowActionsVerified": false, "screenCaptureVerified": false, "realFocusNotificationsVerified": false,
                                         "ownedSpaceMetadata": spaceEvidence, "externalSpaceFocusVerified": false,
                                         "ownedNativeTabs": tabEvidence,
                                         "ownedLifecycle": lifecycleEvidence,
                                         "appearanceOptions": appearanceEvidence,
                                         "language": Bundle.main.preferredLocalizations.first ?? "unknown"]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination, options: .atomic)
        } catch {
            let report: [String: Any] = ["passed": false, "error": error.localizedDescription, "checks": checks]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        NSApp.terminate(nil)
    }

    private static func auditSettingsForm(shortcuts: [SwitcherShortcut], destination: URL, checks: inout [String: Bool]) async -> [[String: Any]] {
        var settingsVariants: [[String: Any]] = []
        let settingsController = WindowSwitcherHotkeyController()
        settingsController.saveShortcuts([])
        checks["invalidShortcutEditShowsError"] = settingsController.shortcutEditingError != nil
        settingsController.saveShortcuts(shortcuts)
        checks["validShortcutEditClearsError"] = settingsController.shortcutEditingError == nil
        var invalidActions = SwitcherActionBinding.defaults
        invalidActions[0] = .init(action: .choose, keyCode: 13, modifiers: .command)
        settingsController.saveActionBindings(invalidActions)
        checks["invalidActionEditShowsError"] = settingsController.actionEditingError != nil
        settingsController.saveActionBindings(SwitcherActionBinding.defaults)
        checks["validActionEditClearsError"] = settingsController.actionEditingError == nil
        // cacheDisplay cannot composite glass against the desktop. Render this form with the
        // ordinary app locale and an explicit light appearance for a legible structural snapshot.
        NSApp.appearance = NSAppearance(named: .aqua)
        for width in [760.0, 1000.0] {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: width, height: 680),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: SwitcherSettingsForm(controller: settingsController)
                .environment(\.locale, pocketLocale).preferredColorScheme(.light)
                .background(Color(nsColor: .windowBackgroundColor)))
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(250))
            let compact = accessibilityValues(window)
            checks["settings\(Int(width))CompactHidesCommandLine"] = !compact.contains { $0.contains("--switcher list --detailed") }
            checks["settings\(Int(width))AdvancedToggleAvailable"] = compact.contains(String(localized: "Gelişmiş ayarları göster"))
            let compactURL = destination.deletingLastPathComponent().appendingPathComponent("switcher-settings-compact-\(Int(width)).png")
            checks["settings\(Int(width))CompactSnapshot"] = snapshot(window, to: compactURL)
            checks["settings\(Int(width))AdvancedTogglePress"] = SwitcherAppearanceRuntimeAudit.press(String(localized: "Gelişmiş ayarları göster"), in: window)
            try? await Task.sleep(for: .milliseconds(250))
            checks["settings\(Int(width))AdvancedRevealsCommandLine"] = accessibilityValues(window).contains { $0.contains("--switcher list --detailed") }
            let nodes = ToolUIAudit.accessibilityNodes(window)
            let overflow = nodes.filter { node in
                guard let x = Double(node["x"] ?? ""), let controlWidth = Double(node["width"] ?? ""), controlWidth > 0 else { return false }
                return x < window.frame.minX - 2 || x + controlWidth > window.frame.maxX + 2
            }
            checks["settings\(Int(width))NoMeasuredHorizontalOverflow"] = overflow.isEmpty
            let url = destination.deletingLastPathComponent().appendingPathComponent("switcher-settings-\(Int(width)).png")
            checks["settings\(Int(width))Snapshot"] = snapshot(window, to: url)
            checks["settings\(Int(width))FirstRecorderGranted"] = settingsController.setRecording(true)
            checks["settings\(Int(width))SecondRecorderDenied"] = !settingsController.setRecording(true)
            checks["settings\(Int(width))RecordingLock"] = settingsController.recordingShortcut
            settingsController.stopForModule()
            checks["settings\(Int(width))StopReleasesRecording"] = !settingsController.recordingShortcut
            settingsVariants.append(["width": width, "kind": "full-form", "accessibility": nodes,
                                     "horizontalOverflowHeuristic": overflow, "snapshot": url.lastPathComponent])
            checks["settings\(Int(width))AdvancedCollapsePress"] = SwitcherAppearanceRuntimeAudit.press(String(localized: "Gelişmiş ayarları göster"), in: window)
            try? await Task.sleep(for: .milliseconds(100))
            checks["settings\(Int(width))CollapsedHidesCommandLine"] = !accessibilityValues(window).contains { $0.contains("--switcher list --detailed") }
            window.orderOut(nil)
        }
        return settingsVariants
    }

    private static func fixtureWindows() -> [SwitchableWindow] {
        let titles = ["MacPocket — çalışma alanı", "Haftalık rapor — uzun pencere başlığı", "Terminal — geliştirme"]
        return (0..<3).map { index -> SwitchableWindow in
            let pid: Int32 = index == 2 ? Int32.max : ProcessInfo.processInfo.processIdentifier
            return SwitchableWindow(id: "fixture-\(index)", processID: pid, application: "MacPocket Fixture",
                  title: titles[index],
                  applicationURL: Bundle.main.bundleURL, minimized: false, hidden: false, fullScreen: false,
                  frontmost: index == 0, windowAccessible: true, canClose: true, canMinimize: true, canFullScreen: true,
                  launchedAt: nil, lastFocusedAt: nil, windowID: UInt32(index + 1))
        }
    }

    private static func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<150 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static func auditEnvironmentRefresh(fixture: AuditCapture, checks: inout [String: Bool]) async {
        var old = fixtureWindows(), fresh = fixtureWindows()
        let visible = WindowSpace(id: 11, ordinal: 1, displayIdentifier: "Fixture", kind: .desktop, visible: true)
        let hidden = WindowSpace(id: 12, ordinal: 2, displayIdentifier: "Fixture", kind: .desktop, visible: false)
        old[0].spaceMembership = .init(spaces: [visible]); old[1].spaceMembership = .init(spaces: [hidden])
        fresh[0].spaceMembership = .init(spaces: [hidden]); fresh[1].spaceMembership = .init(spaces: [visible])
        var shortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab, modifiers: .option, releaseBehavior: .hold)
        shortcut.filter.spaceScope = .visible; shortcut.presentation.style = .titles; shortcut.presentation.order = .space
        let catalog = AuditCatalog(windows: old)
        let model = WindowSwitcherModel(windows: old, catalog: catalog, previews: fixture, permitsCapture: { true })
        let controller = WindowSwitcherHotkeyController(model: model, foregroundApplication: { NSRunningApplication.current })
        model.selection = "fixture-0"
        _ = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        model.beginSearch(); model.sessionSearch = "Fixture"
        await catalog.pauseReads()
        let oldRead = Task { await model.refresh() }
        _ = await waitUntil { await catalog.waitingReads > 0 }
        await catalog.setWindows(fresh)
        for _ in 0..<3 {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        }
        checks["spaceNotificationStartsPreparation"] = await waitUntil { controller.preparingForAudit }
        if let panel = controller.auditPanel { await sendKey(48, to: panel) }
        await catalog.resumeReads()
        await oldRead.value
        checks["spaceNotificationRefreshesEligibleWindows"] = await waitUntil {
            !controller.preparingForAudit && model.filtered.map(\.id) == ["fixture-1", "fixture-2"]
        }
        checks["spaceRefreshRetainsSearchAndQueuedTab"] = model.isSearching && model.sessionSearch == "Fixture" && model.selection == "fixture-2"
        let scans = await catalog.snapshots
        checks["spaceNotificationBurstCoalescesAndDiscardsOldScan"] = scans == 2 && model.windows[0].spaceMembership == fresh[0].spaceMembership
        model.sessionDisplayID = .max
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        _ = await waitUntil { controller.preparingForAudit }
        _ = await waitUntil { !controller.preparingForAudit }
        checks["removedDisplayContextFallsBackWithoutLosingSelection"] = model.sessionDisplayID != nil && model.sessionDisplayID != .max
            && model.selection == "fixture-2" && model.isSearching
        if let panel = controller.auditPanel, let display = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == model.sessionDisplayID
        }) {
            checks["refreshedPanelFitsRemainingDisplay"] = display.visibleFrame.contains(panel.frame)
        }
        controller.stopForModule()

        let releaseCatalog = AuditCatalog(windows: old)
        let releaseModel = WindowSwitcherModel(windows: old, catalog: releaseCatalog, previews: fixture, permitsCapture: { true })
        let releaseController = WindowSwitcherHotkeyController(model: releaseModel, foregroundApplication: { NSRunningApplication.current })
        shortcut.releaseBehavior = .choose
        releaseModel.selection = "fixture-0"
        _ = releaseController.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        await releaseCatalog.setWindows(fresh)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        _ = await waitUntil { releaseController.preparingForAudit }
        releaseController.releaseModifiersForAudit()
        let earlyFocus = await releaseCatalog.focused
        checks["releaseDuringEnvironmentRefreshDoesNotChooseStaleWindow"] = earlyFocus.isEmpty && releaseController.preparingForAudit
        checks["releaseDuringEnvironmentRefreshChoosesFreshTarget"] = await waitUntil { await releaseCatalog.focused == ["fixture-1"] }
        checks["releaseDuringEnvironmentRefreshClosesPanel"] = releaseController.auditPanel?.isVisible != true
        releaseController.stopForModule()

        let closedCatalog = AuditCatalog(windows: old)
        let closedModel = WindowSwitcherModel(windows: old, catalog: closedCatalog, previews: fixture, permitsCapture: { true })
        let closedController = WindowSwitcherHotkeyController(model: closedModel, foregroundApplication: { NSRunningApplication.current })
        _ = closedController.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        if let panel = closedController.auditPanel { await sendKey(53, to: panel) }
        await closedCatalog.setWindows(fresh)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        try? await Task.sleep(for: .milliseconds(20))
        await closedCatalog.pauseReads()
        closedController.show(shortcut: shortcut)
        _ = await waitUntil { await closedCatalog.waitingReads > 0 }
        closedController.releaseModifiersForAudit()
        let closedEarlyFocus = await closedCatalog.focused
        checks["closedSpaceChangeInvalidatesWarmCommit"] = closedEarlyFocus.isEmpty && closedController.preparingForAudit
        await closedCatalog.resumeReads()
        checks["reopenedSessionChoosesFreshEnvironment"] = await waitUntil { await closedCatalog.focused == ["fixture-1"] }
        closedController.stopForModule()

        let dismissCatalog = AuditCatalog(windows: old)
        let dismissModel = WindowSwitcherModel(windows: old, catalog: dismissCatalog, previews: fixture, permitsCapture: { true })
        let dismissController = WindowSwitcherHotkeyController(model: dismissModel)
        shortcut.releaseBehavior = .hold
        _ = dismissController.beginVisualAudit(reduceTransparency: true, shortcut: shortcut)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        _ = await waitUntil { dismissController.preparingForAudit }
        if let panel = dismissController.auditPanel { await sendKey(53, to: panel) }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        try? await Task.sleep(for: .milliseconds(230))
        let dismissedScans = await dismissCatalog.snapshots
        checks["dismissAndClosedSessionCancelEnvironmentScan"] = dismissedScans == 0 && dismissController.auditPanel?.isVisible != true
        dismissController.stopForModule()
        checks["environmentObservationStopsWithModule"] = dismissController.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
    }

    /// Real WindowServer reads against an owned AppKit window. A native fullscreen transition
    /// creates and removes only that window's Space; no external application is focused or mutated.
    private static func auditOwnedSpaceMetadata(anchorID: UInt32, checks: inout [String: Bool]) async -> [String: Any] {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 140, width: 560, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = String(localized: "MacPocket · Masaüstü testi")
        window.collectionBehavior = [.fullScreenPrimary]
        let transition = FullscreenAuditTransition()
        let entered = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { transition.entered = true }
        }
        let exited = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { transition.exited = true }
        }
        defer { NotificationCenter.default.removeObserver(entered); NotificationCenter.default.removeObserver(exited) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(250))
        let id = UInt32(window.windowNumber)
        let provider = WindowSpaceProvider.shared
        var before = await provider.snapshot(windowIDs: [id])
        let normalReady = await waitUntil {
            before = await provider.snapshot(windowIDs: [id])
            return before.membership(for: id)?.isVisible == true && before.membership(for: id)?.firstOrdinal != nil
        }
        checks["ownedNormalWindowMembershipSettlesBeforeBaseline"] = normalReady
        let normal = before.membership(for: id)
        checks["ownedSpaceTopologyAvailable"] = before.available
        checks["ownedNormalWindowHasVisibleMembership"] = normal?.isVisible == true && normal?.firstOrdinal != nil
        let catalog = WindowCatalog()
        let report = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        let entry = report.windows.first { $0.windowID == id }
        checks["productionCatalogAnnotatesOwnedWindow"] = report.spaceMetadataAvailable && entry?.spaceMembership?.isVisible == true
            && entry?.spaceMembership?.spaces.map(\.id) == normal?.spaces.map(\.id)
        let liveCatalog = OwnedReadOnlyCatalog(catalog: catalog, allowedIDs: [id, anchorID])
        let liveModel = WindowSwitcherModel(windows: report.windows.filter { $0.windowID == id || $0.windowID == anchorID },
                                            catalog: liveCatalog, permitsCapture: { false })
        let liveController = WindowSwitcherHotkeyController(model: liveModel, foregroundApplication: { NSRunningApplication.current })
        var liveShortcut = SwitcherShortcut(keyCode: SwitcherKeys.tab, modifiers: .option, releaseBehavior: .hold)
        liveShortcut.filter.spaceScope = .visible; liveShortcut.presentation.style = .titles
        liveShortcut.presentation.order = .space
        liveModel.selection = entry?.id
        _ = liveController.beginVisualAudit(reduceTransparency: true, shortcut: liveShortcut)
        window.miniaturize(nil)
        let minimizeDeadline = Date().addingTimeInterval(3)
        while !window.isMiniaturized, Date() < minimizeDeadline { try? await Task.sleep(for: .milliseconds(30)) }
        try? await Task.sleep(for: .milliseconds(200))
        let minimized = await provider.snapshot(windowIDs: [id])
        checks["ownedMinimizedWindowRetainsSpaceMembership"] = window.isMiniaturized && minimized.membership(for: id)?.isVisible == true
            && minimized.membership(for: id)?.spaces.map(\.id) == normal?.spaces.map(\.id)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(250))
        window.toggleFullScreen(nil)
        var fullscreen = WindowSpaceSnapshot()
        let enterDeadline = Date().addingTimeInterval(6)
        while Date() < enterDeadline {
            fullscreen = await provider.snapshot(windowIDs: [id])
            if transition.entered, window.styleMask.contains(.fullScreen), fullscreen.membership(for: id)?.isVisible == true,
               fullscreen.membership(for: id)?.spaces.contains(where: { $0.kind == .fullScreen }) == true { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        checks["ownedFullscreenSpaceHasDistinctMembership"] = transition.entered && window.styleMask.contains(.fullScreen)
            && fullscreen.membership(for: id)?.isVisible == true
            && fullscreen.membership(for: id)?.spaces.contains(where: { $0.kind == .fullScreen }) == true
            && fullscreen.membership(for: id)?.spaces.map(\.id) != normal?.spaces.map(\.id)
        let liveEnterDeadline = Date().addingTimeInterval(5)
        while Date() < liveEnterDeadline {
            if !liveController.preparingForAudit,
               liveModel.windows.first(where: { $0.windowID == id })?.spaceMembership?.spaces.map(\.id) == fullscreen.membership(for: id)?.spaces.map(\.id),
               !liveModel.filtered.contains(where: { $0.windowID == anchorID }) { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        checks["ownedSpaceNotificationUpdatesOpenProductionPanel"] = !liveController.preparingForAudit
            && liveModel.windows.first(where: { $0.windowID == id })?.spaceMembership?.spaces.map(\.id) == fullscreen.membership(for: id)?.spaces.map(\.id)
            && liveModel.filtered.contains(where: { $0.windowID == id }) && !liveModel.filtered.contains(where: { $0.windowID == anchorID })
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        var restored = WindowSpaceSnapshot()
        let exitDeadline = Date().addingTimeInterval(6)
        while Date() < exitDeadline {
            restored = await provider.snapshot(windowIDs: [id])
            if transition.exited, !window.styleMask.contains(.fullScreen), restored.membership(for: id)?.spaces.map(\.id) == normal?.spaces.map(\.id),
               Set(restored.spaces.map(\.id)) == Set(before.spaces.map(\.id)) { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        checks["ownedFullscreenFixtureRestoresOriginalSpace"] = transition.exited && !window.styleMask.contains(.fullScreen)
            && restored.membership(for: id)?.spaces.map(\.id) == normal?.spaces.map(\.id)
        checks["ownedSpaceFixtureRemovesTemporaryDesktop"] = Set(restored.spaces.map(\.id)) == Set(before.spaces.map(\.id))
        let liveExitDeadline = Date().addingTimeInterval(5)
        while Date() < liveExitDeadline {
            if !liveController.preparingForAudit,
               liveModel.windows.first(where: { $0.windowID == id })?.spaceMembership?.spaces.map(\.id) == normal?.spaces.map(\.id),
               liveModel.filtered.contains(where: { $0.windowID == anchorID }) { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        checks["ownedSpaceNotificationRestoresOpenPanelScope"] = !liveController.preparingForAudit
            && liveModel.windows.first(where: { $0.windowID == id })?.spaceMembership?.spaces.map(\.id) == normal?.spaces.map(\.id)
            && liveModel.filtered.contains(where: { $0.windowID == anchorID })
        let liveReads = await liveCatalog.snapshots
        liveController.stopForModule()
        window.close()
        return ["source": "WindowServer-private-read-only-API-and-owned-AppKit-window",
                "normalSpaceIDs": normal?.spaces.map(\.id) ?? [],
                "fullscreenSpaceIDs": fullscreen.membership(for: id)?.spaces.map(\.id) ?? [],
                "restoredSpaceIDs": restored.membership(for: id)?.spaces.map(\.id) ?? [],
                "normalTopologyIDs": before.spaces.map(\.id), "restoredTopologyIDs": restored.spaces.map(\.id),
                "openPanelCatalogReads": liveReads, "openPanelCatalogSource": "production-owned-process-only-read-only-catalog",
                "fullscreenTransition": "owned-window-only", "didEnterFullscreen": transition.entered,
                "didExitFullscreen": transition.exited, "externalSpaceFocusVerified": false]
    }

    private static func auditConcurrentCatalogSnapshots(checks: inout [String: Bool]) async {
        func ownedWindow(at offset: CGFloat) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 90 + offset, y: 140 + offset, width: 350, height: 240),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.tabbingMode = .disallowed
            window.title = String(localized: "MacPocket · Masaüstü testi")
            window.makeKeyAndOrderFront(nil)
            return window
        }
        let first = ownedWindow(at: 0)
        try? await Task.sleep(for: .milliseconds(120))
        let gate = DelayedOwnedSpaceProvider()
        let catalog = WindowCatalog(spaceProvider: gate)
        let oldRead = Task { await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true) }
        checks["concurrentOwnedCatalogOldSnapshotIsPaused"] = await waitUntil { await gate.waiting }
        let second = ownedWindow(at: 40)
        try? await Task.sleep(for: .milliseconds(120))
        let fresh = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        let target = fresh.windows.first { $0.windowID == UInt32(second.windowNumber) }?.id
        let presentBefore = if let target { await catalog.hasActionHandleForAudit(target) } else { false }
        checks["concurrentOwnedCatalogNewWindowHasHandle"] = presentBefore
        await gate.release()
        let old = await oldRead.value
        let presentAfter = if let target { await catalog.hasActionHandleForAudit(target) } else { false }
        checks["lateOwnedCatalogSnapshotCannotRevokeFreshHandle"] = presentAfter
            && !old.windows.contains(where: { $0.windowID == UInt32(second.windowNumber) })
        first.close(); second.close()
    }

    static func sendKey(_ code: UInt16, to window: NSWindow, characters: String = "", modifiers: NSEvent.ModifierFlags = []) async {
        // A fixture dispatch is addressed to this owned panel. Restore its key status if a
        // native snapshot or external interaction changed it; this is not a physical-input test.
        if !NSApp.isActive {
            syntheticFocusRestorations += 1
            NSApp.activate(ignoringOtherApps: true)
            let deadline = Date().addingTimeInterval(1)
            while !NSApp.isActive, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        }
        if !window.isKeyWindow { syntheticFocusRestorations += 1; window.makeKeyAndOrderFront(nil) }
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
            NSApp.sendEvent(event)
            // Let native presentation/focus transactions finish before reading their result.
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    static func snapshot(_ window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }

    /// SwiftUI's private accessibility nodes can expose values through the informal AppKit
    /// attribute API even when they do not implement the formal NSAccessibilityProtocol getters.
    static func accessibilityValues(_ root: NSObject) -> [String] {
        var seen = Set<ObjectIdentifier>(), pending = [root], values: [String] = []
        while let element = pending.popLast(), seen.count < 2_000 {
            guard seen.insert(ObjectIdentifier(element)).inserted else { continue }
            for name in ["accessibilityValue", "accessibilityTitle", "accessibilityLabel"] {
                let selector = NSSelectorFromString(name)
                if element.responds(to: selector), let value = element.perform(selector)?.takeUnretainedValue() as? String {
                    values.append(value)
                }
            }
            let attribute = NSSelectorFromString("accessibilityAttributeValue:")
            if element.responds(to: attribute) {
                for key in [NSAccessibility.Attribute.value, .title, .description] {
                    if let value = element.perform(attribute, with: key.rawValue)?.takeUnretainedValue() as? String { values.append(value) }
                }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if element.responds(to: children) {
                pending += element.perform(children)?.takeUnretainedValue() as? [NSObject] ?? []
            }
        }
        return values
    }
}

@MainActor private final class FullscreenAuditTransition { var entered = false; var exited = false }

private actor DelayedOwnedSpaceProvider: WindowSpaceProviding {
    private var reads = 0
    private var pending: CheckedContinuation<Void, Never>?
    var waiting: Bool { pending != nil }
    func release() { pending?.resume(); pending = nil }
    func snapshot(windowIDs: [UInt32]) async -> WindowSpaceSnapshot {
        reads += 1
        let first = reads == 1
        let snapshot = await WindowSpaceProvider.shared.snapshot(windowIDs: windowIDs)
        if first { await withCheckedContinuation { pending = $0 } }
        return snapshot
    }
}

/// The production reader is scoped to owned windows. Mutation is intentionally unavailable here.
private actor OwnedReadOnlyCatalog: WindowCatalogServing {
    let catalog: WindowCatalog
    let allowedIDs: Set<UInt32>
    private(set) var snapshots = 0
    init(catalog: WindowCatalog, allowedIDs: Set<UInt32>) { self.catalog = catalog; self.allowedIDs = allowedIDs }
    func snapshot() async -> WindowCatalogReport {
        snapshots += 1
        let report = await catalog.snapshot(processIDs: [getpid()], includingCurrentApplication: true)
        return .init(windows: report.windows.filter { $0.windowID.map(allowedIDs.contains) == true },
                     accessibilityGranted: report.accessibilityGranted, partial: report.partial, otherSpacesVisible: report.otherSpacesVisible,
                     spaceMetadataAvailable: report.spaceMetadataAvailable, spaceMetadataPartial: report.spaceMetadataPartial)
    }
    func focus(_ id: String) async throws { throw WindowCatalogError.unsupported }
    func perform(_ action: WindowAction, on id: String) async throws { throw WindowCatalogError.unsupported }
    func noteApplicationActivation(_ pid: Int32) async {}
}

private actor AuditCatalog: WindowCatalogServing {
    private(set) var windows: [SwitchableWindow]
    private(set) var focused: [String] = []
    private(set) var actions: [String] = []
    private(set) var snapshots = 0
    private var paused = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    var waitingReads: Int { pending.count }
    init(windows: [SwitchableWindow]) { self.windows = windows }
    func setWindows(_ windows: [SwitchableWindow]) { self.windows = windows }
    func pauseReads() { paused = true }
    func resumeReads() { paused = false; let reads = pending; pending.removeAll(); for read in reads { read.resume() } }
    func snapshot() async -> WindowCatalogReport {
        snapshots += 1
        let captured = windows
        if paused { await withCheckedContinuation { pending.append($0) } }
        return .init(windows: captured, accessibilityGranted: true, partial: false)
    }
    func focus(_ id: String) async throws { focused.append(id) }
    func perform(_ action: WindowAction, on id: String) async throws { actions.append(String(describing: action)) }
    func noteApplicationActivation(_ pid: Int32) async {}
}

private struct ShortcutOptionsAuditView: View {
    @State var shortcut: SwitcherShortcut
    var body: some View {
        Form { SwitcherShortcutOptions(shortcut: shortcut, update: { shortcut = $0 }) }
            .formStyle(.grouped)
            .environment(\.locale, pocketLocale)
    }
}

private struct FilterOptionsAuditView: View {
    @State var filter: WindowListFilter
    var body: some View {
        Form { SwitcherFilterOptions(filter: $filter) }
            .formStyle(.grouped)
            .environment(\.locale, pocketLocale)
    }
}

private struct AuditCapture: WindowPreviewCapturing {
    let image: WindowImage

    @MainActor init() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let label = NSTextField(wrappingLabelWithString: "MacPocket\nWindow switcher fixture\n\nOption + Tab → select\nRelease Option → switch")
        label.font = .monospacedSystemFont(ofSize: 24, weight: .medium)
        label.frame = NSRect(x: 32, y: 48, width: 570, height: 300)
        view.addSubview(label)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw WindowPreviewError.unavailable }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let cgImage = bitmap.cgImage else { throw WindowPreviewError.unavailable }
        image = WindowImage(cgImage: cgImage)
    }

    func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage { image }
}
#endif
