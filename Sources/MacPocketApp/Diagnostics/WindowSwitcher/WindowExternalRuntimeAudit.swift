#if DEBUG
import AppKit
@preconcurrency import ApplicationServices
import Darwin
import MacPocketCore

/// Explicit acceptance entry point, before AppState. The fixture is a separately built, owned app;
/// no global hotkeys, preferences, normal modules or permission requests are started here.
@MainActor enum WindowExternalRuntimeAudit {
    static func runIfRequested() {
        TransferFilePanelController.runIfRequested()
        WindowExistingFocusRuntimeAudit.runIfRequested()
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--audit-switcher-external") else { return }
        guard Bundle.main.bundleIdentifier == "com.doancan.MacPocket", args.indices.contains(index + 2) else { exit(2) }
        let fixture = URL(fileURLWithPath: args[index + 2]).standardizedFileURL.resolvingSymlinksInPath()
        guard fixture.lastPathComponent == "WindowFixture.WindowFixtureAudit.app",
              Bundle(url: fixture)?.bundleIdentifier == "com.doancan.MacPocket.WindowFixtureAudit" else { exit(2) }
        let driver = ExternalAuditDriver(destination: URL(fileURLWithPath: args[index + 1]), fixture: fixture)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = driver
        withExtendedLifetime(driver) { app.run() }
        exit(0)
    }
}

@MainActor private final class ExternalAuditDriver: NSObject, NSApplicationDelegate {
    let destination: URL, fixture: URL
    private let previous = NSWorkspace.shared.frontmostApplication
    private var sequence = 0
    private var folder: URL
    private var checks: [String: Bool] = [:]
    private var evidence: [String: Any] = [:]
    init(destination: URL, fixture: URL) {
        self.destination = destination
        self.fixture = fixture
        folder = destination.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await run(); NSApp.terminate(nil) }
    }
    private func run() async {
        let process = Process()
        let focusLease = WindowFocusObservation(), lifecycle = WindowLifecycleObservation()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            evidence = ["source": "production-AXUIElement-ScreenCaptureKit-and-owned-external-AppKit-process",
                        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "applicationStateStarted": false,
                        "fixtureApplication": fixture.path, "fixtureDirectory": folder.lastPathComponent,
                        "accessibilityGranted": AXIsProcessTrusted(), "screenCaptureGranted": WindowPreviewProvider.permitted,
                        "physicalHotkeysVerified": false, "unownedApplicationsVerified": false,
                        "voiceOverVerified": false, "physicalMultipleDisplaysVerified": false]
            let cliOnly = CommandLine.arguments.contains("--only-cli")
            let carbonProbeOnly = CommandLine.arguments.contains("--only-carbon-hotkey")
            let cancelManualOnly = CommandLine.arguments.contains("--only-manual-keyboard-cancel")
            let manualKeyboardOnly = CommandLine.arguments.contains("--only-manual-keyboard") || cancelManualOnly
            let systemCommandOnly = CommandLine.arguments.contains("--only-system-command-tab") || manualKeyboardOnly
            let commandProbeOnly = CommandLine.arguments.contains("--only-command-tab-probe") || CommandLine.arguments.contains("--only-command-tab-reset")
            guard AXIsProcessTrusted(), cliOnly || commandProbeOnly || carbonProbeOnly || systemCommandOnly || WindowPreviewProvider.permitted else { throw WindowCatalogError.permissionRequired }
            if manualKeyboardOnly,!WindowPreviewProvider.permitted { throw WindowPreviewError.permissionRequired }
            process.executableURL = fixture.appendingPathComponent("Contents/MacOS/WindowFixture")
            process.arguments = [folder.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let pid = process.processIdentifier
            evidence["fixturePID"] = pid
            checks["ownedExternalProcessPublishesTwoWindowIDs"] = await wait { self.id("A") != nil && self.id("B") != nil }
            guard let a = id("A"), let b = id("B"), process.isRunning else { throw WindowCatalogError.expired }
            let catalog = ScopedExternalCatalog(pid: pid, applicationURL: fixture)
            var report = await catalog.snapshot()
            checks["productionAXAdmitsBothOwnedExternalWindows"] = await wait {
                report = await catalog.snapshot()
                return [a,b].allSatisfy { id in report.windows.contains { $0.windowID == id && $0.windowAccessible } }
            }
            guard let windowA = report.windows.first(where: { $0.windowID == a }),
                  let windowB = report.windows.first(where: { $0.windowID == b }) else { throw WindowCatalogError.expired }
            checks["sameTitlesHaveDifferentProcessBoundIdentities"] = windowA.title == windowB.title && windowA.id != windowB.id
                && windowA.launchedAt != nil && windowA.launchedAt == windowB.launchedAt && report.windows.allSatisfy { $0.processID == pid }
            if systemCommandOnly {
                evidence["source"] = "production-Carbon-registration-and-WindowServer-state-with-owned-guard-processes"
                evidence["screenCaptureExercised"] = false
                var systemChecks: [String:Bool] = [:]
                let result: [String:Any]
                if manualKeyboardOnly {
                    let manualCatalog = SwitcherManualFocusCatalog(catalog)
                    result = await SwitcherSystemCommandTabAudit.run(catalog: manualCatalog,checks: &systemChecks,manualExercise: { controller in
                        try await SwitcherManualKeyboardAudit.run(controller: controller,catalog: manualCatalog,expectedID: windowA.id,fixturePID: pid,expectedWindow: a,autoCancel: cancelManualOnly,
                            guideSnapshot: self.destination.appendingPathComponent("manual-keyboard-guide.png"),
                            activateFixture: { try await self.command("focus",key: "A") },focusedWindow: { self.focusedWindow(pid) })
                    })
                    evidence["source"] = "physical-Carbon-input-and-owned-AX-SCK-fixture"
                    evidence["physicalHotkeysVerified"] = result["physicalKeyboardVerified"] as? Bool ?? false
                    let manualData = result["manualKeyboard"] as? [String:Any] ?? [:]
                    evidence["screenCaptureExercised"] = manualData["guideScreenshotCaptured"] as? Bool == true || (manualData["phases"] as? [[String:Any]] ?? []).contains { $0["sawThumbnails"] as? Bool == true }
                    evidence["expectedManualCancellation"] = cancelManualOnly
                } else { result = await SwitcherSystemCommandTabAudit.run(catalog: catalog,checks: &systemChecks) }
                checks.merge(systemChecks,uniquingKeysWith: { _,new in new })
                evidence["systemCommandTab"] = result
                if result["error"] != nil || result["restorationError"] != nil { checks["systemCommandTabCompletesWithoutError"] = false }
            } else if carbonProbeOnly {
                evidence["source"] = "controlled-generated-input-Carbon-feasibility-probe"
                evidence["screenCaptureExercised"] = false
                let result = try await CarbonHotkeyRuntimeProbe.run(fixturePID: pid) { try await self.command("focus",key: "A") }
                checks.merge(result.0,uniquingKeysWith: { _,new in new })
                evidence["carbonHotkeyProbe"] = result.1
            } else if CommandLine.arguments.contains("--only-performance") {
                var performanceChecks: [String:Bool] = [:]
                defer { checks.merge(performanceChecks,uniquingKeysWith: { _,new in new }) }
                evidence["performance"] = try await SwitcherPerformanceRuntimeAudit.run(catalog: catalog,checks: &performanceChecks)
            } else if commandProbeOnly {
                evidence["source"] = "controlled-generated-Command-Tab-filter-probe"
                evidence["screenCaptureExercised"] = false
                let result = try await CommandTabInputProbe.run(fixturePID: pid) { try await self.command("focus",key: "A") }
                checks.merge(result.0,uniquingKeysWith: { _,new in new })
                evidence["commandTabProbe"] = result.1
            } else if cliOnly {
                try await auditCLI(first: windowA,second: windowB,catalog: catalog)
            } else {
            try await auditDockBadges(first: windowA,second: windowB)
            evidence["initialCatalog"] = rows(report)
            lifecycle.start()
            try await command("focus", key: "A")
            checks["fixtureIsForegroundBeforeObservation"] = await wait { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && self.focusedWindow(pid) == a }
            focusLease.start()
            checks["productionExternalAXFocusObserverAttached"] = await wait { WindowFocusObservation.diagnosticResources["axObservers"] == 1 }
            try await command("focus", key: "B")
            checks["externalAXFocusNotificationCreatesTwoHistoryRecords"] = await wait { (WindowFocusObservation.diagnosticResources["focusRecords"] ?? 0) >= 2 }
            report = await catalog.snapshot()
            checks["externalFocusNotificationSetsMRU"] = WindowFiltering.apply(report.windows, order: .recent).first?.windowID == b
            focusLease.stop()
            try await catalog.focus(windowA.id)
            checks["productionFocusRaisesExactSameTitleWindowA"] = await wait { self.focusedWindow(pid) == a && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
            try await catalog.focus(windowB.id)
            checks["productionFocusRaisesExactSameTitleWindowB"] = await wait { self.focusedWindow(pid) == b }

            let previews = WindowPreviewProvider()
            let imageA = try await previews.image(for: windowA, maxPixels: CGSize(width: 640, height: 480))
            let imageB = try await previews.image(for: windowB, maxPixels: CGSize(width: 640, height: 480))
            let colorA = mean(imageA.cgImage), colorB = mean(imageB.cgImage)
            checks["screenCaptureKitSameTitleWindowAIsRed"] = colorA[0] > colorA[1] * 2 && colorA[0] > colorA[2] * 2
            checks["screenCaptureKitSameTitleWindowBIsGreen"] = colorB[1] > colorB[0] * 2 && colorB[1] > colorB[2] * 2
            checks["screenCaptureKitRespectsPixelBudget"] = [imageA,imageB].allSatisfy { $0.cgImage.width <= 640 && $0.cgImage.height <= 480 }
            try save(imageA.cgImage, name: "external-A-red.png")
            try save(imageB.cgImage, name: "external-B-green.png")
            try await command("repaint", key: "A")
            try? await Task.sleep(for: .milliseconds(180))
            let repainted = try await previews.image(for: windowA, maxPixels: CGSize(width: 640, height: 480))
            let blue = mean(repainted.cgImage)
            checks["screenCaptureKitRecapturesChangedContentWithoutChangingIdentity"] = blue[2] > blue[0] * 2 && blue[2] > blue[1] * 2
            try save(repainted.cgImage, name: "external-A-blue.png")
            evidence["captureColorsRGB"] = ["A": colorA, "B": colorB, "updatedA": blue]
            evidence["capturePixelSizes"] = ["A": [imageA.cgImage.width,imageA.cgImage.height], "B": [imageB.cgImage.width,imageB.cgImage.height]]

            try await catalog.perform(.minimize, on: windowA.id)
            checks["productionAXMinimizeChangesOwnedWindow"] = await wait { self.window("A")["minimized"] as? Bool == true }
            report = await catalog.snapshot()
            checks["productionCatalogReadsRealMinimizedState"] = report.windows.first { $0.windowID == a }?.minimized == true
            try await catalog.focus(windowA.id)
            checks["productionFocusRestoresMinimizedTarget"] = await wait { self.window("A")["minimized"] as? Bool == false && self.focusedWindow(pid) == a }
            try await catalog.perform(.hideApplication, on: windowA.id)
            checks["productionHideChangesOwnedApplication"] = await wait { self.state()["hidden"] as? Bool == true }
            report = await catalog.snapshot()
            evidence["hiddenCatalog"] = rows(report)
            checks["hiddenOwnedWindowsRemainInProductionCatalog"] = [a,b].allSatisfy { id in report.windows.contains { $0.windowID == id && $0.hidden } }
            checks["hiddenWindowBPreservesIdentity"] = report.windows.contains { $0.id == windowB.id }
            evidence["unhideActionIdentity"] = await catalog.diagnostics(windowB.id)
            try await catalog.focus(windowB.id)
            checks["productionFocusUnhidesExactTarget"] = await wait { self.state()["hidden"] as? Bool == false && self.focusedWindow(pid) == b }

            // The real HUD uses the scoped production catalog and real SCK provider.
            let model = WindowSwitcherModel(catalog: catalog, previews: previews)
            await model.refresh()
            model.selection = windowA.id
            let controller = WindowSwitcherHotkeyController(model: model)
            var shortcut = SwitcherShortcut.defaultOptionTab
            shortcut.presentation.style = .thumbnails
            shortcut.presentation.showThumbnails = true
            shortcut.releaseBehavior = .hold
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            shortcut.presentation.previewSelected = true
            if let panel = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) {
                checks["productionHUDCapturesBothExternalWindows"] = await wait { model.thumbnails[windowA.id] != nil && model.thumbnails[windowB.id] != nil }
                checks["productionHUDShowsRealFullSizePreview"] = await wait { controller.previewVisibleForAudit }
                checks["productionHUDSnapshot"] = WindowSwitcherRuntimeAudit.snapshot(panel, to: destination.appendingPathComponent("external-HUD.png"))
                model.selection = windowA.id
                controller.commitForAudit()
                checks["productionHUDCommitFocusesSelectedExternalID"] = await wait { self.focusedWindow(pid) == a && controller.auditPanel?.isVisible != true }
                evidence["hudCommitState"] = ["fixture": state(),"focusedID": focusedWindow(pid).map(Int.init) ?? -1,
                    "frontPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,"auditKeyWindow": NSApp.keyWindow?.windowNumber ?? -1,"panelIsKey": controller.auditPanel?.isKeyWindow ?? false,"modelFailure": model.failure ?? "nil", "identity": await catalog.diagnostics(windowA.id)]
            } else { checks["productionHUDPanelAvailable"] = false }
            controller.stopForModule()
            checks["productionHUDStopReleasesResources"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
            try await auditBadgeFocusComparison(first: windowA,second: windowB,catalog: catalog)
            if !CommandLine.arguments.contains("--only-badge-focus") {
            try await auditLiveCapture(windowA, catalog: catalog)
            try await auditDisplays(catalog: catalog, a: a, b: b, pid: pid)

            try await command("tabs")
            checks["fixtureActuallyCreatesTwoNativeTabs"] = await wait { (self.window("A")["tabs"] as? [Int])?.count == 2 }
            report = await catalog.snapshot()
            evidence["nativeTabsCatalog"] = rows(report)
            evidence["nativeTabsAXTree"] = tree(pid)
            let tabs = report.windows.filter { $0.nativeTab != nil }
            checks["productionRemoteAXDiscoversNativeTabButtons"] = tabs.count == 2
            if let background = tabs.first(where: { $0.nativeTab?.selected == false }) {
                checks["backgroundNativeTabHasNoGuessedCaptureID"] = background.windowID == nil && !background.canCapturePreview
                try await catalog.focus(background.id)
                checks["productionRemoteAXPressSelectsActualNativeTabB"] = await wait { self.window("A")["selectedTab"] as? UInt32 == b && self.focusedWindow(pid) == b }
                try await command("rename", key: "B")
                let renamed = await catalog.snapshot()
                checks["productionRemoteAXReadsRenamedTab"] = renamed.windows.contains { $0.nativeTab != nil && $0.title.hasSuffix(" · B") }
            }

            try await command("create", key: "E")
            try await command("create", key: "C")
            var third = await catalog.snapshot()
            checks["productionCatalogAdmitsNewOwnedWindow"] = await wait {
                third = await catalog.snapshot()
                return self.id("C").map { id in third.windows.contains { $0.windowID == id && $0.windowAccessible } } == true
            }
            if let c = id("C"), let target = third.windows.first(where: { $0.windowID == c }) {
                let ruleSuite = "com.doancan.MacPocket.ExternalExceptionAudit." + UUID().uuidString
                guard let ruleDefaults = UserDefaults(suiteName: ruleSuite) else { throw WindowCatalogError.focusFailed }
                defer { ruleDefaults.removePersistentDomain(forName: ruleSuite) }
                let fixtureBundleID = "com.doancan.MacPocket.WindowFixtureAudit"
                checks["externalCatalogPreservesBundleIdentityForNativeTabsAndPhysicalWindows"] = !third.windows.isEmpty && third.windows.allSatisfy { $0.bundleIdentifier == fixtureBundleID }
                let titleRule = SwitcherExceptionRule(target: .bundlePrefix,value: "com.doancan.MacPocket.WindowFixture",visibility: .titleContains,titlePatterns: [" · B"])
                var tabFilter = WindowListFilter()
                tabFilter.separateTabs = true
                let visibleTabs = WindowFiltering.apply(third.windows,filter: tabFilter,exceptions: [titleRule]).filter { $0.nativeTab != nil }
                checks["externalTitleRuleHidesOnlyRenamedBackgroundTab"] = visibleTabs.count == 1 && visibleTabs.first?.title.hasSuffix(" · B") == false
                checks["externalConditionalRulePersists"] = SwitcherExceptionStore.save([.init(target: .bundleIdentifier,value: fixtureBundleID,shortcuts: .fullscreen)],ruleDefaults)
                try await catalog.focus(target.id)
                checks["externalConditionalBaselineHasExactFocusedWindow"] = await wait { self.focusedWindow(pid) == c && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
                let conditionalController = WindowSwitcherHotkeyController(model: WindowSwitcherModel(defaults: ruleDefaults))
                conditionalController.updateExceptionsForAudit()
                defer { conditionalController.stopForModule() }
                if let app = NSRunningApplication(processIdentifier: pid) {
                    let initial = await SwitcherForegroundWindowReader.shared.isFullscreen(SwitcherForegroundApplication(app))
                    checks["externalFocusedWindowReaderRecognizesWindowedState"] = initial == false
                }
                var beforeSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: [a,b,c])
                checks["ownedFullscreenBaselineTopologyIsStable"] = await wait {
                    beforeSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: [a,b,c])
                    return beforeSpaces.available && !beforeSpaces.partial && beforeSpaces.membership(for: c)?.isVisible == true
                }
                evidence["beforeFullscreenSpaces"] = beforeSpaces.spaces.map { ["id": $0.id, "visible": $0.visible, "display": $0.displayIdentifier] }
                try await catalog.perform(.toggleFullScreen, on: target.id)
                checks["productionAXEntersOwnedFullscreenSpace"] = await wait(seconds: 8) {
                    self.window("C")["fullscreen"] as? Bool == true && self.window("C")["fullscreenPhase"] as? String == "fullscreen"
                }
                checks["externalFullscreenRuleSuspendsWithoutApplicationActivation"] = await wait { conditionalController.suspendedForApplication != nil }
                checks["externalExceptionAuditTakesNoGlobalKeys"] = conditionalController.moduleDiagnosticResources["hotKeys"] == 0 && conditionalController.moduleDiagnosticResources["handler"] == 0
                var spaceReport = await catalog.snapshot()
                checks["productionRemoteTabsSurviveOtherSpace"] = await wait(seconds: 8) {
                    spaceReport = await catalog.snapshot()
                    return spaceReport.windows.filter { $0.nativeTab != nil && $0.isOnAnotherSpace }.count == 2
                }
                evidence["otherSpaceCatalog"] = rows(spaceReport)
                evidence["otherSpaceAXTree"] = tree(pid)
                evidence["otherSpaceLists"] = await spaceLists([a,b,c])
                if let offSpaceTab = spaceReport.windows.first(where: { $0.nativeTab?.selected == false && $0.isOnAnotherSpace }) {
                    let originalSpaces = Set(offSpaceTab.spaceMembership?.spaces.map(\.id) ?? [])
                    let start = ContinuousClock.now
                    do {
                        let cursorModel = WindowSwitcherModel(windows: spaceReport.windows,catalog: catalog,permitsCapture: { false })
                        guard await cursorModel.focus(id: offSpaceTab.id,cursorPolicy: .always) else { throw WindowCatalogError.focusFailed }
                        checks["productionCrossSpaceTabFocusRequestSucceeds"] = true
                    } catch {
                        checks["productionCrossSpaceTabFocusRequestSucceeds"] = false
                        evidence["crossSpaceFocusError"] = String(describing: error)
                    }
                    checks["productionCrossSpaceTabFocusSelectsExactWindow"] = await wait(seconds: 8) { self.focusedWindow(pid) == a }
                    checks["productionCrossSpaceTabFocusMakesTargetSpaceVisible"] = await wait(seconds: 8) {
                        let actual = await WindowSpaceProvider.shared.snapshot(windowIDs: [a,b,c])
                        return !originalSpaces.isDisjoint(with: actual.spaces.filter(\.visible).map(\.id)) && self.focusedWindow(pid) == a
                    }
                    checks["productionCrossSpaceTabKeepsOriginalSpaceMembership"] = await wait(seconds: 8) {
                        let landed = await WindowSpaceProvider.shared.snapshot(windowIDs: [a,b,c])
                        return !originalSpaces.isEmpty && landed.memberships[a] == originalSpaces
                    }
                    let elapsed = start.duration(to: .now).components
                    let focusedTabDestination = await catalog.focusDestination(offSpaceTab.id)
                    checks["cursorCrossSpaceTabDestinationResolvesSelectedPhysicalWindow"] = focusedTabDestination?.windowID == a && focusedTabDestination?.processID == pid
                    checks["cursorCrossSpaceTabGetsPointerOnItsOriginalSpace"] = await wait {
                        guard let frame = focusedTabDestination?.frame,let point = CGEvent(source: nil)?.location else { return false }
                        return hypot(point.x-frame.midX,point.y-frame.midY) < 2
                    }
                    evidence["crossSpaceFocus"] = ["targetID": offSpaceTab.id, "expectedPhysicalID": a,
                        "focusedWindowID": focusedWindow(pid).map(Int.init) ?? -1,
                        "elapsedMilliseconds": Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                        "spaces": await spaceLists([a,b,c])]
                } else { checks["productionCrossSpaceTabTargetAvailable"] = false }
                checks["externalFullscreenSiblingDoesNotKeepDesktopTabSuspended"] = await wait { conditionalController.suspendedForApplication == nil }
                try await catalog.focus(target.id)
                checks["productionFocusReturnsToExistingFullscreenSpace"] = await wait(seconds: 8) {
                    let current = await WindowSpaceProvider.shared.snapshot(windowIDs: [c])
                    return current.membership(for: c)?.isVisible == true && self.focusedWindow(pid) == c
                }
                checks["externalFullscreenRuleSuspendsAgainOnReturn"] = await wait { conditionalController.suspendedForApplication != nil }
                if let e = id("E") {
                    let cold = ScopedExternalCatalog(pid: pid, applicationURL: fixture)
                    let offSpace = await cold.snapshot()
                    if let destination = offSpace.windows.first(where: { $0.windowID == e }) {
                        let beforeGeometry = window("E")
                        checks["coldCrossSpaceTargetHasNoCachedAXWindow"] = !destination.windowAccessible && destination.nativeTab == nil && destination.isOnAnotherSpace
                        let expected = Set(destination.spaceMembership?.spaces.map(\.id) ?? [])
                        do { try await cold.focus(destination.id); checks["coldCrossSpaceWindowFocusRequestSucceeds"] = true }
                        catch { checks["coldCrossSpaceWindowFocusRequestSucceeds"] = false; evidence["coldCrossSpaceError"] = String(describing: error) }
                        checks["externalFullscreenRuleResumesOnColdDesktopWindow"] = await wait { conditionalController.suspendedForApplication == nil }
                        evidence["coldCrossSpaceActivationDiagnostics"] = await cold.diagnostics(destination.id)
                        checks["coldCrossSpaceWindowFocusSelectsExactWindow"] = await wait(seconds: 8) { self.focusedWindow(pid) == e }
                        checks["coldCrossSpaceWindowPreservesMembershipAndSwitchesDesktop"] = await wait(seconds: 8) {
                            let current = await WindowSpaceProvider.shared.snapshot(windowIDs: [e,c])
                            return !expected.isEmpty && current.memberships[e] == expected && current.membership(for: e)?.isVisible == true
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                        let afterGeometry = window("E")
                        checks["coldCrossSpaceActivationDoesNotResizeOrMoveWindow"] = ["x","y","width","height"].allSatisfy {
                            guard let before = beforeGeometry[$0] as? Double, let after = afterGeometry[$0] as? Double else { return false }
                            return abs(before - after) < 1
                        }
                        checks["coldCrossSpaceActivationDoesNotClickWindowContent"] = afterGeometry["contentMouseEvents"] as? Int == 0
                        evidence["coldCrossSpaceFocus"] = ["windowID": e,"focusedID": focusedWindow(pid).map(Int.init) ?? -1,
                                                          "listedAX": tree(pid),"spaces": await spaceLists([e,c]),
                                                          "beforeGeometry": beforeGeometry,"afterGeometry": afterGeometry]
                    } else { checks["coldCrossSpaceWindowTargetAvailable"] = false }
                } else { checks["coldCrossSpaceWindowTargetAvailable"] = false }
                try await command("fullscreen", key: "C")
                checks["ownedFullscreenRoundtripRestoresOriginalSpaceTopology"] = await wait(seconds: 8) {
                    let now = await WindowSpaceProvider.shared.snapshot(windowIDs: [a,b,c])
                    return self.window("C")["fullscreen"] as? Bool == false && self.window("C")["fullscreenPhase"] as? String == "windowed" && now.spaces == beforeSpaces.spaces
                }
                let restoredSpaces = await WindowSpaceProvider.shared.snapshot(windowIDs: [a,b,c])
                evidence["restoredFullscreenSpaces"] = restoredSpaces.spaces.map { ["id": $0.id, "visible": $0.visible, "display": $0.displayIdentifier] }
                _ = await catalog.snapshot()
                let closingModel = WindowSwitcherModel(windows: third.windows, catalog: catalog, permitsCapture: { false })
                await closingModel.action(.close, id: target.id)
                checks["productionAXCloseClosesOnlyOwnedTarget"] = await wait { self.window("C")["visible"] as? Bool == false }
                checks["productionModelRemovesRetainedCloseAfterAnimation"] = await wait { !closingModel.windows.contains { $0.windowID == c } }
                closingModel.stopObserving()
                evidence["retainedCloseSpaceLists"] = await spaceLists([a,b,c])
                try? await Task.sleep(for: .milliseconds(700))
                evidence["retainedCloseSpaceListsAfter700ms"] = await spaceLists([a,b,c])
                let closed = await catalog.snapshot()
                evidence["retainedClose"] = ["id": c, "physicalSurfaceStillExists": rawWindow(c, pid: pid),
                                             "catalog": rows(closed), "AXTree": tree(pid)]
                checks["retainedClosedWindowIsNotOffSpaceGhost"] = !closed.windows.contains { $0.windowID == c }
                checks["retainedClosedWindowHasNoActionHandle"] = !(await catalog.hasHandle(target.id))
                try await command("release", key: "C")
            }
            try await command("release", key: "E")
            try await command("release", key: "A")
            try await command("release", key: "B")
            try await command("create", key: "D")
            var last = await catalog.snapshot()
            checks["productionCatalogAdmitsLastReopenTestWindow"] = await wait {
                last = await catalog.snapshot()
                return self.id("D").map { id in last.windows.contains { $0.windowID == id && $0.windowAccessible } } == true
            }
            if let d = id("D"), let target = last.windows.first(where: { $0.windowID == d }) {
                try await catalog.perform(.close, on: target.id)
                var windowless = await catalog.snapshot()
                checks["lastRetainedCloseBecomesWindowlessApplication"] = await wait {
                    windowless = await catalog.snapshot()
                    return windowless.windows.count == 1 && windowless.windows.first?.isRealWindow == false
                }
                checks["windowlessApplicationDoesNotKeepClosedWindowHandle"] = !(await catalog.hasHandle(target.id))
                let noWindowRule = SwitcherExceptionRule(target: .bundleIdentifier,value: "com.doancan.MacPocket.WindowFixtureAudit",visibility: .windowless)
                checks["externalWindowlessExceptionHidesTheActualWindowlessApplication"] = WindowFiltering.apply(windowless.windows,exceptions: [noWindowRule]).isEmpty
                try await command("reopen", key: "D")
                checks["reopenedSameRetainedWindowIsAdmittedAgain"] = await wait {
                    let reopened = await catalog.snapshot()
                    return reopened.windows.contains { $0.windowID == d && $0.windowAccessible }
                }
                let reopened = await catalog.snapshot()
                checks["externalWindowlessExceptionKeepsTheReopenedPhysicalWindow"] = !reopened.windows.isEmpty
                    && WindowFiltering.apply(reopened.windows,exceptions: [noWindowRule]).count == reopened.windows.count
            }
            }
            }
        } catch {
            evidence["error"] = String(describing: error)
            if process.isRunning {
                evidence["fixtureStateAtFailure"] = state()
                evidence["fixtureAXTreeAtFailure"] = tree(process.processIdentifier)
            }
        }
        focusLease.stop()
        lifecycle.stop()
        if process.isRunning {
            try? await command("exit")
            let ended = await wait(seconds: 10) { !process.isRunning }
            checks["ownedExternalProcessExitsAndRestoresItsSpaces"] = ended && process.terminationReason == .exit && process.terminationStatus == 0
            if process.isRunning { process.terminate() }
        }
        if !CommandLine.arguments.contains("--only-cli"),!CommandLine.arguments.contains("--only-command-tab-probe"),!CommandLine.arguments.contains("--only-command-tab-reset"),!CommandLine.arguments.contains("--only-performance"),!CommandLine.arguments.contains("--only-carbon-hotkey"),!CommandLine.arguments.contains("--only-system-command-tab"),!CommandLine.arguments.contains("--only-manual-keyboard"),!CommandLine.arguments.contains("--only-manual-keyboard-cancel") {
            var editorChecks: [String: Bool] = [:]
            evidence["exceptionEditor"] = await SwitcherExceptionsRuntimeAudit.run(destination: destination, checks: &editorChecks)
            checks.merge(editorChecks, uniquingKeysWith: { _, new in new })
        }
        if let previous, !previous.isTerminated { previous.activate(options: []) }
        evidence["checks"] = checks
        evidence["passed"] = evidence["error"] == nil && !checks.isEmpty && checks.values.allSatisfy { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted,.sortedKeys]) {
            try? data.write(to: destination.appendingPathComponent("report.json"), options: .atomic)
        }
    }
    /// The actual bundled CLI talks to the production listener/service and a PID/URL-scoped
    /// real catalog. Only windows in the separately owned fixture may be mutated.
    private func auditCLI(first: SwitchableWindow,second: SwitchableWindow,catalog: ScopedExternalCatalog) async throws {
        let suite = "MacPocket.ExternalCLIAudit."+UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite),let executable = Bundle.main.executableURL,
              let a = first.windowID,let b = second.windowID else { throw WindowCatalogError.expired }
        defer { defaults.removePersistentDomain(forName: suite) }
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.releaseBehavior = .hold
        shortcut.presentation.style = .titles
        shortcut.presentation.showThumbnails = false
        shortcut.presentation.previewSelected = false
        shortcut.presentation.showBadges = false
        shortcut.presentation.animateOpening = false
        shortcut.presentation.animateClosing = false
        SwitcherShortcutStore.save([shortcut],defaults)
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults,permitsCapture: { false })
        model.startObserving()
        let controller = WindowSwitcherHotkeyController(model: model,gestureSettings: defaults)
        controller.beginGestureAudit()
        defer { controller.stopForModule() }
        let service = SwitcherCommandService(controller: controller)
        let listener = try SwitcherCLIListener { await service.execute($0) }
        defer { listener.stop() }
        var traces: [[String:Any]] = []
        func cli(_ arguments: [String]) async throws -> (Int32,SwitcherCLIResponse?) {
            let result = try await BoundedProcess.run(executable.path,["--switcher"]+arguments,timeout: 28)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try? decoder.decode(SwitcherCLIResponse.self,from: Data(result.output.utf8))
            traces.append(["arguments": arguments,"exit": result.status,"status": response?.status ?? "",
                "errorCode": response?.errorCode ?? "","targetID": response?.targetID ?? "","stderr": result.errorOutput,
                "focusedID": focusedWindow(first.processID).map(Int.init) ?? -1,"frontPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                "fixture": state()])
            return (result.status,response)
        }
        func exact(_ id: UInt32,_ key: String) -> Bool {
            focusedWindow(first.processID) == id && NSWorkspace.shared.frontmostApplication?.processIdentifier == first.processID
                && window(key)["key"] as? Bool == true && window(key)["main"] as? Bool == true
        }
        let originalGeometry = ["A": window("A"),"B": window("B")]
        evidence["source"] = "production-CLI-CFMessagePort-AXUIElement-owned-external-AppKit-process"
        evidence["cliFocusUsesRealCatalog"] = true
        evidence["screenCaptureExercised"] = false
        evidence["cliProfileDefaults"] = "isolated-suite"
        evidence["cliGlobalHotkeysRegistered"] = false
        evidence["cliUsesOrdinaryModelFocusAndLifecycleLeases"] = true
        let compact = try await cli(["list"]),detailed = try await cli(["list","--detailed"])
        checks["cliExternalListHasTwoSameTitleDistinctIDs"] = compact.0 == 0 && compact.1?.windows?.count == 2
            && Set(compact.1?.windows?.map(\.id) ?? []).count == 2 && Set(compact.1?.windows?.map(\.title) ?? []).count == 1
        checks["cliExternalCompactListOmitsDetails"] = compact.1?.windows?.allSatisfy { $0.details == nil } == true
        checks["cliExternalDetailedListMatchesRealPIDAndWindowIDs"] = detailed.0 == 0 && detailed.1?.accessibility == true
            && Set(detailed.1?.windows?.compactMap(\.windowID) ?? []) == [a,b]
            && detailed.1?.windows?.allSatisfy { $0.details?.processID == first.processID && $0.details?.actionable == true } == true
        let firstFocus = try await cli(["focus",first.id])
        let actualFirst = await wait { exact(a,"A") }
        checks["cliExternalOpaqueIDFocusesExactWindowA"] = firstFocus.0 == 0 && firstFocus.1?.targetID == first.id && actualFirst
        let secondFocus = try await cli(["focus",String(b)])
        let actualSecond = await wait { exact(b,"B") }
        checks["cliExternalNumericIDFocusesExactWindowB"] = secondFocus.0 == 0 && secondFocus.1?.targetID == second.id && actualSecond
        var mruList: SwitcherCLIResponse?
        checks["cliExternalObservedMRUPlacesWindowBFirst"] = await wait {
            let result = try? await cli(["list"])
            mruList = result?.1
            return mruList?.windows?.first?.windowID == b
        }
        let previous = try await cli(["focus","--mru","2"])
        let actualPrevious = await wait { exact(a,"A") }
        checks["cliExternalMRU2FocusesPreviousWindowA"] = previous.0 == 0 && previous.1?.targetID == first.id && actualPrevious
        try await catalog.perform(.minimize,on: first.id)
        checks["cliExternalSetupMinimizesOwnedTarget"] = await wait { self.window("A")["minimized"] as? Bool == true }
        let restored = try await cli(["focus",String(a)])
        let actuallyRestored = await wait { exact(a,"A") && self.window("A")["minimized"] as? Bool == false }
        checks["cliExternalFocusRestoresMinimizedTarget"] = restored.0 == 0 && actuallyRestored
        try await catalog.perform(.hideApplication,on: second.id)
        checks["cliExternalSetupHidesOwnedApplication"] = await wait { self.state()["hidden"] as? Bool == true }
        let hidden = try await cli(["list","--detailed"])
        checks["cliExternalListReportsHiddenWindows"] = hidden.0 == 0 && hidden.1?.windows?.count == 2 && hidden.1?.windows?.allSatisfy { $0.details?.hidden == true } == true
        let unhidden = try await cli(["focus",second.id])
        let actuallyUnhidden = await wait { exact(b,"B") && self.state()["hidden"] as? Bool == false }
        checks["cliExternalFocusUnhidesExactTarget"] = unhidden.0 == 0 && actuallyUnhidden
        // Repeat the asynchronous unhide path with alternating same-title targets; checking
        // AXFocusedWindow alone previously missed an application that never became foreground.
        for index in 0..<3 {
            let target = index % 2 == 0 ? first : second,key = index % 2 == 0 ? "A" : "B"
            try await catalog.perform(.hideApplication,on: target.id)
            checks["cliExternalHiddenCycle-\(index)-Setup"] = await wait { self.state()["hidden"] as? Bool == true }
            let reply = try await cli(["focus",target.id])
            let actual = await wait { exact(target.windowID!,key) && self.state()["hidden"] as? Bool == false }
            checks["cliExternalHiddenCycle-\(index)-ExactForeground"] = reply.0 == 0 && reply.1?.status == "focused" && actual
        }
        let baselineB = try await cli(["focus",second.id])
        let baselineReady = await wait { exact(b,"B") }
        checks["cliExternalRestoresBForPanelChecks"] = baselineB.0 == 0 && baselineReady
        let shown = try await cli(["show","1"])
        let actuallyShown = await wait { !controller.preparingForAudit && controller.commandPanelVisible }
        checks["cliExternalShowCreatesNativePanelWithoutCommit"] = shown.0 == 0 && actuallyShown
            && focusedWindow(first.processID) == b
        let selection = model.selection
        let again = try await cli(["show","1"]),status = try await cli(["status"])
        checks["cliExternalRepeatedShowPreservesSelection"] = again.0 == 0 && model.selection == selection
        checks["cliExternalStatusMatchesRealVisiblePanel"] = status.0 == 0 && status.1?.panelVisible == true && controller.auditPanel?.isVisible == true
        model.selection = first.id
        let hide = try await cli(["hide"])
        let actualAfterHide = await wait { exact(b,"B") }
        checks["cliExternalHideDoesNotCommitDifferentSelectedCard"] = hide.0 == 0 && hide.1?.panelVisible == false && !controller.commandPanelVisible && actualAfterHide
        _ = try await cli(["show","1"])
        _ = await wait { !controller.preparingForAudit && controller.commandPanelVisible }
        model.selection = second.id
        let fromPanel = try await cli(["focus",first.id])
        let actualFromPanel = await wait { exact(a,"A") }
        checks["cliExternalExplicitFocusOverridesOpenPanelSelection"] = fromPanel.0 == 0 && !controller.commandPanelVisible && actualFromPanel
        let missing = try await cli(["focus","missing-owned-cli-window"])
        checks["cliExternalMissingIDFailsWithoutChangingFocus"] = missing.0 == 2 && missing.1?.errorCode == "not-found" && exact(a,"A")
        let invalid = try await cli(["focus","--mru","0"])
        checks["cliExternalInvalidMRUFailsBeforeChangingFocus"] = invalid.0 == 1 && invalid.1 == nil && exact(a,"A")
        let invalidProfile = try await cli(["show","9"])
        checks["cliExternalMissingProfileFailsWithoutOpeningPanel"] = invalidProfile.0 == 2 && invalidProfile.1?.errorCode == "unavailable" && !controller.commandPanelVisible
        let geometryUnchanged = ["A","B"].allSatisfy { key in
            ["x","y","width","height","contentMouseEvents"].allSatisfy { field in
                guard let before = originalGeometry[key]?[field] as? NSNumber,let after = window(key)[field] as? NSNumber else { return false }
                return before == after
            }
        }
        checks["cliExternalFocusDoesNotClickContentsOrChangeGeometry"] = geometryUnchanged
        _ = try await cli(["focus",second.id])
        _ = await wait { exact(b,"B") }
        try await command("release",key: "A")
        checks["cliExternalSetupReleasesPhysicalWindowA"] = await wait { self.id("A") == nil && !self.rawWindow(a,pid: first.processID) }
        let stale = try await cli(["focus",first.id])
        checks["cliExternalExpiredIDCannotFocusAnotherWindow"] = stale.0 == 2 && stale.1?.errorCode == "not-found" && exact(b,"B")
        evidence["cliTraces"] = traces
        evidence["cliInitialMRU"] = mruList?.windows?.map { ["id": $0.id,"mru": String($0.mru)] } ?? []
        controller.stopForModule()
        checks["cliExternalStopReleasesAllControllerResources"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }
        checks["cliExternalStopReleasesFocusAndLifecycleLeases"] = WindowFocusObservation.diagnosticResources["owners"] == 0
            && WindowLifecycleObservation.diagnosticResources["owners"] == 0
    }
    private func state() -> [String: Any] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    private func auditLiveCapture(_ target: SwitchableWindow, catalog: ScopedExternalCatalog) async throws {
        let previews = ExternalCaptureCounter()
        let model = WindowSwitcherModel(windows: [target], catalog: catalog, previews: previews)
        model.selection = target.id
        let worker = Task { await model.runThumbnails(maxPixels: CGSize(width: 640,height: 480), live: true) }
        defer { worker.cancel(); model.clearThumbnails() }
        checks["productionLiveQueueCapturesInitialExternalImage"] = await wait { model.thumbnails[target.id] != nil }
        try await command("repaint", key: "A")
        checks["productionLiveQueueRefreshesChangedExternalPixels"] = await wait {
            guard let image = model.thumbnails[target.id]?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            let rgb = self.mean(image)
            return rgb[0] > rgb[2] * 2 && rgb[0] > rgb[1] * 2
        }
        let oldSession = model.thumbnailSessionID
        model.clearThumbnails()
        worker.cancel()
        await worker.value
        let count = await previews.count
        try? await Task.sleep(for: .milliseconds(100))
        let stoppedCount = await previews.count
        checks["productionLiveQueueStopsWithoutPublishingAfterEnd"] = count == stoppedCount && model.thumbnailSessionID != oldSession && model.selectedPreview == nil
        evidence["liveCaptureRequests"] = count
    }
    private func window(_ key: String) -> [String: Any] { (state()["windows"] as? [String: [String: Any]])?[key] ?? [:] }
    private func id(_ key: String) -> UInt32? { (window(key)["id"] as? NSNumber)?.uint32Value }
    private func command(_ action: String, key: String = "A", origin: CGPoint? = nil,label: String? = nil) async throws {
        sequence += 1
        let request = sequence
        var payload: [String: Any] = ["sequence": request, "action": action, "key": key]
        if let label { payload["label"] = label }
        if let origin { payload["x"] = origin.x; payload["y"] = origin.y }
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: folder.appendingPathComponent("command.json"), options: .atomic)
        guard await wait({ self.state()["sequence"] as? Int == request }) else { throw WindowCatalogError.expired }
    }
    private func auditBadgeFocusComparison(first: SwitchableWindow,second: SwitchableWindow,catalog: ScopedExternalCatalog) async throws {
        var traces: [[String:Any]] = []
        try await command("badge",label: "7")
        for (index,enabled) in [false,true,false,true].enumerated() {
            try await command("focus",key: "B")
            let baseline = await wait { self.focusedWindow(first.processID) == second.windowID }
            let model = WindowSwitcherModel(catalog: catalog,permitsCapture: { false })
            await model.refresh()
            let controller = WindowSwitcherHotkeyController(model: model)
            var shortcut = SwitcherShortcut.defaultOptionTab
            shortcut.presentation.style = .titles
            shortcut.presentation.showBadges = enabled
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            shortcut.presentation.previewSelected = false
            _ = controller.beginVisualAudit(reduceTransparency: true,shortcut: shortcut)
            if enabled {
                checks["badgeFocusRealDockValueArrives-\(index)"] = await wait { model.applicationBadge(for: first)?.label == "7" && model.applicationBadge(for: second)?.label == "7" }
            } else { try? await Task.sleep(for: .milliseconds(100)) }
            model.selection = first.id
            controller.commitForAudit()
            var samples: [[String:Any]] = []
            let committed = await wait {
                let focused = self.focusedWindow(first.processID).map(Int.init) ?? -1
                if samples.last?["focusedID"] as? Int != focused { samples.append(["focusedID": focused,"fixture": self.state()]) }
                return focused == first.windowID.map(Int.init) && controller.auditPanel?.isVisible != true
            }
            checks["badgeFocusComparison-\(index)-\(enabled)"] = baseline && committed
            traces.append(["enabled": enabled,"baseline": baseline,"committed": committed,"samples": samples,"modelFailure": model.failure ?? "nil", "identity": await catalog.diagnostics(first.id)])
            controller.stopForModule()
        }
        try await command("badge")
        evidence["badgeFocusComparison"] = traces
    }
    private func auditDockBadges(first: SwitchableWindow,second: SwitchableWindow) async throws {
        guard let target = DockBadgeTarget(first) else { checks["dockBadgeHasOwnedApplicationIdentity"] = false;return }
        let reader = DockApplicationBadgeReader()
        checks["dockBadgeTwoOwnedWindowsHaveSameApplicationIdentity"] = DockBadgeTarget(second) == target
        var received: [DockBadgeTarget:DockApplicationBadge] = [:]
        for label in ["7","!","12345678901234567890"] {
            try await command("badge",label: label)
            checks["dockBadgeReadsOwnedLabel-" + label] = await wait {
                received = await reader.badges(for: [target])
                return received[target]?.label == label
            }
        }
        if let stale = DockBadgeTarget(processID: target.processID,launchedAt: target.launchedAt.addingTimeInterval(1),applicationURL: target.applicationURL) {
            let rejected = await reader.badges(for: [stale])
            checks["dockBadgeRejectsWrongProcessLaunch"] = rejected.isEmpty
        }
        if let otherPath = DockBadgeTarget(processID: target.processID,launchedAt: target.launchedAt,applicationURL: URL(fileURLWithPath: "/Applications/Other-WindowFixture.app")) {
            let rejected = await reader.badges(for: [otherPath])
            checks["dockBadgeRejectsWrongApplicationPath"] = rejected.isEmpty
        }
        try await command("badge")
        checks["dockBadgeClearRemovesOwnedLabel"] = await wait {
            received = await reader.badges(for: [target])
            return received.isEmpty
        }
        evidence["ownedDockBadge"] = ["source": "real-Dock-AXStatusLabel-and-owned-AppKit-dockTile","application": target.applicationURL.path,
            "processID": target.processID,"labels": ["7","!","12345678901234567890"],"unownedLabelsRead": false]
    }
    private func auditDisplays(catalog: ScopedExternalCatalog, a: UInt32, b: UInt32, pid: Int32) async throws {
        let screens = NSScreen.screens
        evidence["screenCount"] = screens.count
        guard let primary = screens.first(where: { screenID($0) == CGMainDisplayID() }),
              let other = screens.first(where: { screenID($0) != CGMainDisplayID() }),
              let primaryID = screenID(primary), let otherID = screenID(other) else {
            evidence["multipleDisplayAcceptance"] = "requires-two-connected-displays"
            return
        }
        let originalMouse = CGEvent(source: nil)?.location
        defer { if let originalMouse { CGWarpMouseCursorPosition(originalMouse) } }
        let originalA = CGPoint(x: window("A")["x"] as? Double ?? 140, y: window("A")["y"] as? Double ?? 190)
        let originalB = CGPoint(x: window("B")["x"] as? Double ?? 140, y: window("B")["y"] as? Double ?? 190)
        try await command("move", key: "A", origin: CGPoint(x: other.visibleFrame.minX + 40,y: other.visibleFrame.minY + 60))
        try await command("move", key: "B", origin: CGPoint(x: primary.visibleFrame.minX + 40,y: primary.visibleFrame.minY + 60))
        try await command("focus", key: "A")
        checks["displayFixturePlacesWindowsOnDifferentConnectedDisplays"] = await wait {
            self.window("A")["screenID"] as? UInt32 == otherID && self.window("B")["screenID"] as? UInt32 == primaryID && self.focusedWindow(pid) == a
        }
        let mouse = CGPoint(x: primary.visibleFrame.midX,y: primary.visibleFrame.midY)
        let height = screens.first?.frame.maxY ?? primary.frame.maxY
        let warp = CGWarpMouseCursorPosition(CGPoint(x: mouse.x,y: height - mouse.y))
        let positioned = await wait { hypot(NSEvent.mouseLocation.x - mouse.x,NSEvent.mouseLocation.y - mouse.y) < 2 }
        checks["displayPointerCanBePositionedProgrammatically"] = warp == .success && positioned
        var details: [[String: Any]] = []
        for policy in SwitcherScreenPolicy.allCases {
            let model = WindowSwitcherModel(catalog: catalog, permitsCapture: { false })
            await model.refresh()
            let controller = WindowSwitcherHotkeyController(model: model)
            var shortcut = SwitcherShortcut.defaultOptionTab
            shortcut.presentation.screen = policy
            shortcut.presentation.style = .titles
            shortcut.presentation.previewSelected = false
            shortcut.presentation.animateOpening = false
            shortcut.presentation.animateClosing = false
            shortcut.filter.currentScreenOnly = true
            let expected = policy == .activeWindow ? otherID : primaryID
            let expectedWindow = policy == .activeWindow ? a : b
            if let panel = controller.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) {
                try? await Task.sleep(for: .milliseconds(120))
                let prefix = "connectedDisplay-" + policy.rawValue
                checks[prefix + "PanelAndFilterUseSameDisplay"] = model.sessionDisplayID == expected && panel.screen.flatMap(screenID) == expected
                    && Set(model.filtered.compactMap(\.windowID)) == [expectedWindow]
                let onScreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly,0) as? [[String: Any]] ?? []
                checks[prefix + "HUDIsActuallyOnscreen"] = onScreen.contains { $0[kCGWindowNumber as String] as? Int == panel.windowNumber && $0[kCGWindowOwnerPID as String] as? Int32 == getpid() }
                checks[prefix + "Snapshot"] = WindowSwitcherRuntimeAudit.snapshot(panel,to: destination.appendingPathComponent(prefix + ".png"))
                details.append(["policy": policy.rawValue,"expectedDisplayID": expected,"actualDisplayID": model.sessionDisplayID ?? 0,
                                "panelFrame": NSStringFromRect(panel.frame),"windowIDs": model.filtered.compactMap(\.windowID)])
            } else { checks["connectedDisplay-" + policy.rawValue + "PanelAvailable"] = false }
            controller.stopForModule()
        }
        evidence["connectedDisplays"] = details
        evidence["displayPointerInput"] = "programmatic-CGWarpMouseCursorPosition-restored-after-test"
        evidence["physicalMultipleDisplaysVerified"] = positioned && checks["displayFixturePlacesWindowsOnDifferentConnectedDisplays"] == true
            && checks.filter { $0.key.hasPrefix("connectedDisplay-") }.values.allSatisfy { $0 }
        try await auditCursorFollowing(catalog: catalog,a: a,b: b,pid: pid)
        try await command("move",key: "A",origin: originalA)
        try await command("move",key: "B",origin: originalB)
        try await command("focus",key: "A")
    }
    private func auditCursorFollowing(catalog: ScopedExternalCatalog,a: UInt32,b: UInt32,pid: Int32) async throws {
        guard let primary = NSScreen.screens.first(where: { screenID($0) == CGMainDisplayID() }) else { return }
        let suite = "MacPocket.CursorExternalAudit." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw WindowCatalogError.focusFailed }
        defer { defaults.removePersistentDomain(forName: suite) }
        let follower = WindowCursorFollower()
        let model = WindowSwitcherModel(catalog: catalog,defaults: defaults,cursorFollower: follower,permitsCapture: { false })
        await model.refresh()
        guard let targetA = model.windows.first(where: { $0.windowID == a }),let targetB = model.windows.first(where: { $0.windowID == b }) else { throw WindowCatalogError.expired }
        let primaryBounds = CGDisplayBounds(screenID(primary) ?? CGMainDisplayID())
        let initial = CGPoint(x: primaryBounds.midX,y: primaryBounds.midY)
        func at(_ point: CGPoint) -> Bool { CGEvent(source: nil).map { hypot($0.location.x-point.x,$0.location.y-point.y) < 2 } ?? false }
        _ = CGWarpMouseCursorPosition(initial)
        checks["cursorExternalOriginIsActuallyOnPrimaryDisplay"] = await wait { at(initial) }
        let cross = await model.focus(id: targetA.id,cursorPolicy: .differentDisplay)
        let aTrace = follower.lastAuditTrace
        let destinationA = await catalog.focusDestination(targetA.id)
        let aCenter = destinationA.map { CGPoint(x: $0.frame.midX,y: $0.frame.midY) }
        checks["cursorExternalFreshDestinationMatchesExactTarget"] = destinationA?.processID == pid && destinationA?.windowID == a && focusedWindow(pid) == a
        let reachedA = await wait { aCenter.map(at) == true }
        checks["cursorExternalDifferentDisplayWarpsToFocusedWindow"] = cross && reachedA
        let pointerAfterA = CGEvent(source: nil)?.location
        let never = await model.focus(id: targetB.id,cursorPolicy: .never)
        checks["cursorExternalNeverLeavesPointerUntouched"] = never && pointerAfterA.map(at) == true && focusedWindow(pid) == b
        checks["cursorExternalBackgroundSiblingCannotSupplyDestination"] = await catalog.focusDestination(targetA.id) == nil
        _ = CGWarpMouseCursorPosition(initial)
        _ = await wait { at(initial) }
        let same = await model.focus(id: targetB.id,cursorPolicy: .differentDisplay)
        checks["cursorExternalSameDisplayPolicyDoesNotWarp"] = same && at(initial)
        let always = await model.focus(id: targetB.id,cursorPolicy: .always)
        let bTrace = follower.lastAuditTrace
        let destinationB = await catalog.focusDestination(targetB.id)
        let bCenter = destinationB.map { CGPoint(x: $0.frame.midX,y: $0.frame.midY) }
        let reachedB = await wait { bCenter.map(at) == true }
        checks["cursorExternalAlwaysWarpsWithinSameDisplay"] = always && reachedB
        checks["cursorExternalWarpDoesNotClickContent"] = window("A")["contentMouseEvents"] as? Int == 0 && window("B")["contentMouseEvents"] as? Int == 0
        try await catalog.perform(.minimize,on: targetA.id)
        checks["cursorExternalTargetIsActuallyMinimized"] = await wait { self.window("A")["minimized"] as? Bool == true }
        _ = CGWarpMouseCursorPosition(initial)
        _ = await wait { at(initial) }
        let restored = await model.focus(id: targetA.id,cursorPolicy: .always)
        let restoredPointer = await wait { aCenter.map(at) == true && self.window("A")["minimized"] as? Bool == false }
        checks["cursorExternalRestoredMinimizedTargetGetsPointer"] = restored && restoredPointer
        evidence["cursorTraces"] = ["A": aTrace,"B": bTrace]
        evidence["cursorFollowing"] = ["input": "programmatic-CGWarpMouseCursorPosition-owned-fixture-only",
            "A": destinationA.map { NSStringFromRect($0.frame) } ?? "nil","B": destinationB.map { NSStringFromRect($0.frame) } ?? "nil",
            "origin": NSStringFromPoint(initial),"after": CGEvent(source: nil).map { NSStringFromPoint($0.location) } ?? "nil"]
    }

    private func screenID(_ screen: NSScreen) -> UInt32? { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    private func wait(seconds: Double = 4, _ condition: @MainActor () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        repeat { if await condition() { return true }; try? await Task.sleep(for: .milliseconds(40)) } while Date() < end
        return false
    }
    private func focusedWindow(_ pid: Int32) -> UInt32? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return number(unsafeDowncast(value, to: AXUIElement.self))
    }
    private func number(_ window: AXUIElement) -> UInt32? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        var number: CGWindowID = 0
        return unsafeBitCast(symbol, to: GetWindow.self)(window, &number) == .success ? number : nil
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func tree(_ pid: Int32) -> [[String: Any]] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        // App menus include system-owned recent-items content. Inspect only the fixture windows.
        var pending: [(AXUIElement,Int)] = ((attribute(application, kAXWindowsAttribute) as? [AXUIElement]) ?? []).map { ($0,0) }
        var result: [[String: Any]] = [], seen = Set<CFHashCode>()
        while let (element,depth) = pending.popLast(), result.count < 256 {
            guard seen.insert(CFHash(element)).inserted else { continue }
            AXUIElementSetMessagingTimeout(element, 0.03)
            var row: [String: Any] = ["depth": depth]
            for name in [kAXRoleAttribute,kAXSubroleAttribute,kAXTitleAttribute,kAXValueAttribute] {
                if let value = attribute(element, name), let text = value as? String { row[name] = text }
                else if let value = attribute(element, name) as? NSNumber { row[name] = value }
            }
            if row[kAXRoleAttribute] as? String == kAXWindowRole as String { row["windowID"] = number(element).map(Int.init) ?? -1 }
            result.append(row)
            if depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] { pending += children.prefix(80).map { ($0,depth+1) } }
        }
        return result
    }
    private func rows(_ report: WindowCatalogReport) -> [[String: Any]] {
        report.windows.map { w in ["id": w.id, "windowID": w.windowID.map(Int.init) ?? -1, "title": w.title,
                                    "accessible": w.windowAccessible, "minimized": w.minimized, "hidden": w.hidden,
                                    "tab": w.nativeTab?.localizedDescription ?? "", "otherSpace": w.isOnAnotherSpace,
                                    "spaces": w.spaceMembership?.spaces.map(\.id) ?? [], "spaceVisibility": w.spaceMembership?.isVisible.map(String.init) ?? "unknown"] }
    }
    private func rawWindow(_ id: UInt32, pid: Int32) -> Bool {
        (CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements],0) as? [[String: Any]] ?? [])
            .contains { $0[kCGWindowNumber as String] as? UInt32 == id && $0[kCGWindowOwnerPID as String] as? Int32 == pid }
    }
    private func spaceLists(_ ids: [UInt32]) async -> [String: Any] {
        let spaces = await WindowSpaceProvider.shared.snapshot(windowIDs: ids)
        var result: [String: Any] = ["spaces": spaces.spaces.map { ["id": $0.id, "visible": $0.visible] },
                                    "membership": Dictionary(uniqueKeysWithValues: ids.map { (String($0),Array(spaces.memberships[$0] ?? [])) })]
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return result }
        defer { dlclose(library) }
        guard let c = dlsym(library,"CGSMainConnectionID"), let q = dlsym(library,"CGSCopyWindowsWithOptionsAndTags") else { return result }
        typealias Connection = @convention(c) () -> UInt32
        typealias List = @convention(c) (UInt32,Int,CFArray,Int,UnsafeMutablePointer<Int>,UnsafeMutablePointer<Int>) -> Unmanaged<CFArray>?
        let query = unsafeBitCast(q,to:List.self), connection = unsafeBitCast(c,to:Connection.self)()
        let spaceIDs = spaces.spaces.map { NSNumber(value: $0.id) } as CFArray
        for flags in [2,7] {
            var set = 0, clear = 0
            if let raw = query(connection,0,spaceIDs,flags,&set,&clear)?.takeRetainedValue(), let numbers = raw as? [NSNumber] {
                let found = Set(numbers.map(\.uint32Value))
                result["list-\(flags)"] = ids.filter { found.contains($0) }
            }
        }
        return result
    }
    private func mean(_ image: CGImage) -> [Double] {
        let rect = CGRect(x: image.width / 3, y: image.height / 3, width: image.width / 3, height: image.height / 3)
        guard let crop = image.cropping(to: rect) else { return [0,0,0] }
        var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
            context.draw(crop, in: CGRect(x: 0,y: 0,width: 32,height: 32))
        }
        return (0..<3).map { channel in stride(from: channel, to: bytes.count, by: 4).reduce(0) { $0 + Double(bytes[$1]) } / 1024 / 255 }
    }
    private func save(_ image: CGImage, name: String) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw WindowPreviewError.unavailable }
        try data.write(to: destination.appendingPathComponent(name), options: .atomic)
    }
}

private actor ScopedExternalCatalog: WindowCatalogServing {
    private let pid: Int32, applicationURL: URL
    private let catalog = WindowCatalog()
    private var admitted = Set<String>()
    init(pid: Int32, applicationURL: URL) { self.pid = pid; self.applicationURL = applicationURL }
    func snapshot() async -> WindowCatalogReport {
        let report = await catalog.snapshot(processIDs: [pid], matchingApplicationURL: applicationURL)
        admitted = Set(report.windows.map(\.id))
        return report
    }
    func focus(_ id: String) async throws { guard admitted.contains(id) else { throw WindowCatalogError.expired }; try await catalog.focus(id) }
    func focusDestination(_ id: String) async -> WindowFocusDestination? { guard admitted.contains(id) else { return nil };return await catalog.focusDestination(id) }
    func perform(_ action: WindowAction, on id: String) async throws { guard admitted.contains(id) else { throw WindowCatalogError.expired }; try await catalog.perform(action, on: id) }
    func noteApplicationActivation(_ pid: Int32) async { if pid == self.pid { await catalog.noteApplicationActivation(pid) } }
    func hasHandle(_ id: String) async -> Bool { await catalog.hasActionHandleForAudit(id) }
    func diagnostics(_ id: String) async -> [String: String] { await catalog.actionDiagnosticsForAudit(id) }
}

private actor ExternalCaptureCounter: WindowPreviewCapturing {
    private let provider = WindowPreviewProvider()
    private(set) var count = 0
    func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage {
        count += 1
        return try await provider.image(for: window, maxPixels: maxPixels)
    }
}
#endif
