#if DEBUG
import AppKit
import Darwin
import MacPocketCore

/// A separate owned process supplies real WindowServer lifecycle events. It runs before
/// AppState, has no global shortcuts/modules/TCC prompts, and can only edit its own windows.
@MainActor enum WindowLifecycleAuditProducer {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard Bundle.main.bundleIdentifier?.hasSuffix(".SwitcherAudit") == true,
              let index = arguments.firstIndex(of: "--audit-switcher-lifecycle-producer") else { return }
        guard arguments.indices.contains(index + 1) else { exit(2) }
        let app = NSApplication.shared
        let driver = LifecycleProducerDriver(folder: URL(fileURLWithPath: arguments[index + 1]))
        app.setActivationPolicy(.regular); app.delegate = driver
        withExtendedLifetime(driver) { app.run() }
        exit(0)
    }
}

@MainActor private final class LifecycleProducerDriver: NSObject, NSApplicationDelegate {
    let folder: URL
    private var timer: Timer?
    private var handled = Set<String>()
    private var seed: NSWindow?, first: NSWindow?, second: NSWindow?, afterStop: NSWindow?
    private var inactiveTab: NSWindow?, hiddenWindow: NSWindow?
    private weak var releasedFirst: NSWindow?
    private var ids: [String: UInt32] = [:]
    private var closedSecond = false
    init(folder: URL) { self.folder = folder }
    func applicationDidFinishLaunching(_ notification: Notification) {
        seed = makeWindow("seed", x: 120)
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.commands() }
        }
        writeState()
    }
    private func makeWindow(_ key: String, x: CGFloat, show: Bool = true) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: x, y: 180, width: 360, height: 240),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isExcludedFromWindowsMenu = true; window.tabbingMode = .disallowed
        window.title = String(localized: "MacPocket · Masaüstü testi")
        if show { window.orderFront(nil) }
        ids[key] = UInt32(window.windowNumber)
        return window
    }
    private func commands() {
        for command in ["create", "release-first", "close-second", "extra", "release-extra", "release-second", "after-stop", "exit"] {
            guard !handled.contains(command), FileManager.default.fileExists(atPath: folder.appendingPathComponent(command).path) else { continue }
            handled.insert(command)
            switch command {
            case "create":
                first = makeWindow("first", x: 340)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self else { return }
                    self.second = self.makeWindow("second", x: 560); self.writeState()
                }
            case "release-first": releasedFirst = first; first?.close(); first = nil
            case "close-second": second?.close(); closedSecond = true
            case "extra":
                inactiveTab = makeWindow("inactiveTab", x: 120, show: false)
                if let seed, let inactiveTab {
                    seed.tabbingMode = .preferred; inactiveTab.tabbingMode = .preferred
                    seed.addTabbedWindow(inactiveTab, ordered: .above); seed.tabGroup?.selectedWindow = seed
                }
                NSApp.hide(nil)
                hiddenWindow = makeWindow("hidden", x: 780, show: false)
                // Hiding commits after the current AppKit turn. Publish actual completed state.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.writeState() }
            case "release-extra": inactiveTab?.close(); hiddenWindow?.close(); inactiveTab = nil; hiddenWindow = nil
            case "release-second": second = nil
            case "after-stop": NSApp.unhideWithoutActivation(); afterStop = makeWindow("afterStop", x: 780)
            case "exit":
                timer?.invalidate(); timer = nil
                first?.close(); second?.close(); seed?.close(); afterStop?.close()
                inactiveTab?.close(); hiddenWindow?.close()
                first = nil; second = nil; seed = nil; afterStop = nil; inactiveTab = nil; hiddenWindow = nil
                NSApp.terminate(nil)
            default: break
            }
            writeState()
        }
        writeState() // Publish actual weak-reference lifetime after the AppKit autorelease turn.
    }
    private func writeState() {
        let state: [String: Any] = ["ids": ids, "closedSecond": closedSecond, "commands": Array(handled),
                                  "applicationHidden": NSApp.isHidden,"firstDeallocated": handled.contains("release-first") && releasedFirst == nil,
                                  "inactiveTabVerified": inactiveTab != nil && seed?.tabGroup?.windows.count == 2 && seed?.tabGroup?.selectedWindow === seed]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("state.json"), options: .atomic)
        }
    }
}

@MainActor enum WindowLifecycleRuntimeAudit {
    static func run(destination: URL, checks: inout [String: Bool]) async throws -> [String: Any] {
        let folder = destination.appendingPathComponent("lifecycle-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let firstLease = WindowLifecycleObservation(), secondLease = WindowLifecycleObservation()
        firstLease.start(); firstLease.start(); secondLease.start()
        defer { firstLease.stop(); secondLease.stop() }
        checks["lifecycleTwoLeasesShareTwoCallbacks"] = WindowLifecycleObservation.diagnosticResources["owners"] == 2
            && WindowLifecycleObservation.diagnosticResources["callbacks"] == 2
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--audit-switcher-lifecycle-producer", folder.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? command("exit", folder: folder)
            if process.isRunning { process.terminate() }
        }
        checks["lifecycleOwnedProducerStarted"] = await waitUntil { ids(folder)["seed"] != nil }
        let pid = process.processIdentifier
        let catalog = WindowCatalog()
        var seed = await catalog.snapshot(processIDs: [pid])
        let seedID = ids(folder)["seed"]
        // didFinishLaunching/file publication can precede NSWorkspace's process inventory.
        // Do not create later windows until the production catalog actually admitted the seed.
        checks["lifecycleProductionCatalogSeedsOwnedExternalWindow"] = await waitUntil {
            seed = await catalog.snapshot(processIDs: [pid])
            return seedID != nil && seed.windows.contains { $0.windowID == seedID }
                && (WindowLifecycleObservation.diagnosticResources["watchedWindows"] ?? 0) >= 1
        }
        checks["lifecycleExistingWindowDoesNotGetInventedCreationDate"] = seed.windows.first { $0.windowID == seedID }?.creationObservation == nil
        try command("create", folder: folder)
        checks["lifecycleOwnedProducerCreatedTwoWindows"] = await waitUntil { ids(folder)["second"] != nil }
        let numbers = ids(folder)
        guard let firstID = numbers["first"], let secondID = numbers["second"], let seedID else {
            checks["lifecycleOwnedIDsAvailable"] = false
            return ["source": "production-WindowServer-observer-and-owned-child-process", "directory": folder.lastPathComponent]
        }
        let launch = seed.windows.first { $0.windowID == seedID }?.launchedAt
        checks["lifecycleBirthsResolveAndSubscribeWithoutCatalogScan"] = await waitUntil {
            guard let launch else { return false }
            let value = await WindowLifecycleProvider().snapshot(admitting: [])
            return [firstID, secondID].allSatisfy { value.creation(for: .init(windowID: $0, processID: pid, launchedAt: launch)) != nil
                && WindowLifecycleObservation.automaticallyResolvedForAudit($0) }
        }
        var fresh = await catalog.snapshot(processIDs: [pid])
        checks["lifecycleBothOwnedBirthsBindToProductionCatalog"] = await waitUntil {
            fresh = await catalog.snapshot(processIDs: [pid])
            return [firstID, secondID].allSatisfy { id in fresh.windows.first { $0.windowID == id }?.creationObservation != nil }
        }
        let sorted = WindowFiltering.apply(Array(fresh.windows.reversed()), order: .creation)
        checks["lifecycleProductionCreationOrderIsOldestFirstThenUnknown"] = Array(sorted.compactMap(\.windowID).prefix(3)) == [firstID, secondID, seedID]
        let birthTrace: [String: Any] = [String(firstID): WindowLifecycleObservation.resolutionForAudit(firstID),
                                       String(secondID): WindowLifecycleObservation.resolutionForAudit(secondID)]
        let visualModel = WindowSwitcherModel(windows: fresh.windows, permitsCapture: { false })
        let visualController = WindowSwitcherHotkeyController(model: visualModel)
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.presentation.order = .creation; shortcut.presentation.style = .titles; shortcut.releaseBehavior = .hold
        visualModel.selection = firstEntryID(fresh, windowID: firstID)
        if let panel = visualController.beginVisualAudit(reduceTransparency: true, shortcut: shortcut) {
            try? await Task.sleep(for: .milliseconds(160))
            checks["lifecycleOwnHUDDoesNotTriggerEnvironmentRefresh"] = !visualController.preparingForAudit
            await WindowSwitcherRuntimeAudit.sendKey(48, to: panel)
            checks["lifecycleCreationOrderDrivesNativeTabNavigation"] = visualModel.selection == firstEntryID(fresh, windowID: secondID)
            checks["lifecycleCreationOrderNativeSnapshot"] = WindowSwitcherRuntimeAudit.snapshot(panel, to: destination.appendingPathComponent("creation-order.png"))
        } else { checks["lifecycleCreationOrderNativePanel"] = false }
        visualController.stopForModule()
        let firstEntry = fresh.windows.first { $0.windowID == firstID }
        let gate = LifecycleSpaceGate()
        let lateCatalog = WindowCatalog(spaceProvider: gate)
        _ = await lateCatalog.snapshot(processIDs: [pid])
        await gate.arm()
        let oldRead = Task { await lateCatalog.snapshot(processIDs: [pid]) }
        checks["lifecycleOldProductionSnapshotPaused"] = await waitUntil { await gate.waiting }
        try command("release-first", folder: folder)
        checks["lifecycleOwnedReleaseActuallyDestroysSurface"] = await waitUntil {
            state(folder)["firstDeallocated"] as? Bool == true && !rawWindowExists(firstID,pid: pid)
        }
        checks["lifecycleRealOwnedDestroyObserved"] = await waitUntil {
            let value = await WindowLifecycleProvider().snapshot(admitting: [])
            return value.invalidates(firstID, since: fresh.lifecycle)
        }
        if let firstEntry {
            do { try await lateCatalog.focus(firstEntry.id); checks["lifecycleDestroyedHandleExpiresBeforeFocus"] = false }
            catch WindowCatalogError.expired { checks["lifecycleDestroyedHandleExpiresBeforeFocus"] = true }
            catch { checks["lifecycleDestroyedHandleExpiresBeforeFocus"] = false }
        } else { checks["lifecycleDestroyedHandleExpiresBeforeFocus"] = false }
        await gate.release()
        let late = await oldRead.value
        checks["lifecycleLateSnapshotCannotRestoreDestroyedWindow"] = !late.windows.contains { $0.windowID == firstID }
            && late.partial
        if let firstEntry { checks["lifecycleLateSnapshotCannotRestoreDestroyedHandle"] = !(await lateCatalog.hasActionHandleForAudit(firstEntry.id)) }
        try command("close-second", folder: folder)
        _ = await waitUntil { state(folder)["closedSecond"] as? Bool == true }
        try? await Task.sleep(for: .milliseconds(250))
        let retained = await WindowLifecycleProvider().snapshot(admitting: [])
        checks["lifecycleRetainedCloseIsNotFalselyCalledDestruction"] = rawWindowExists(secondID, pid: pid)
            && !retained.invalidates(secondID, since: retained)
        try command("extra", folder: folder)
        _ = await waitUntil { ids(folder)["hidden"] != nil }
        let extraIDs = ids(folder)
        var extraTrace: [String: Any] = [:]
        if let tabID = extraIDs["inactiveTab"], let hiddenID = extraIDs["hidden"], let launch {
            checks["lifecycleInactiveNativeTabAndHiddenWindowAreObserved"] = await waitUntil {
                let value = await WindowLifecycleProvider().snapshot(admitting: [])
                return [tabID, hiddenID].allSatisfy { value.creation(for: .init(windowID: $0, processID: pid, launchedAt: launch)) != nil
                    && WindowLifecycleObservation.automaticallyResolvedForAudit($0) }
                    && state(folder)["applicationHidden"] as? Bool == true && state(folder)["inactiveTabVerified"] as? Bool == true
            }
            checks["lifecycleNewHiddenSurfacesAreWatchedWithoutCatalogScan"] = (WindowLifecycleObservation.diagnosticResources["watchedWindows"] ?? 0) >= 4
            extraTrace = [String(tabID): WindowLifecycleObservation.resolutionForAudit(tabID), String(hiddenID): WindowLifecycleObservation.resolutionForAudit(hiddenID)]
            extraTrace["fixtureState"] = state(folder)
            let beforeExtraRelease = await WindowLifecycleProvider().snapshot(admitting: [])
            try command("release-extra", folder: folder)
            checks["lifecycleInactiveAndHiddenDestroyWithoutCatalogScan"] = await waitUntil {
                let value = await WindowLifecycleProvider().snapshot(admitting: [])
                return [tabID, hiddenID].allSatisfy { value.invalidates($0, since: beforeExtraRelease) }
            }
        } else { checks["lifecycleInactiveNativeTabAndHiddenWindowAreObserved"] = false }
        firstLease.stop()
        checks["lifecycleOneLeaseStoppingKeepsCallbackStream"] = WindowLifecycleObservation.diagnosticResources["owners"] == 1
            && WindowLifecycleObservation.diagnosticResources["callbacks"] == 2
        try command("release-second", folder: folder)
        checks["lifecycleLastLeaseStillReceivesOwnedDestroy"] = await waitUntil {
            let value = await WindowLifecycleProvider().snapshot(admitting: [])
            return value.invalidates(secondID, since: retained)
        }
        let oldSession = retained.sessionID
        secondLease.stop()
        checks["lifecycleLastLeaseReleasesRegistrationsAndWatchList"] = WindowLifecycleObservation.diagnosticResources.values.allSatisfy { $0 == 0 }
        try command("after-stop", folder: folder)
        checks["lifecycleOwnedCreationAfterStopHasNoObserver"] = await waitUntil { ids(folder)["afterStop"] != nil }
        let stopped = await WindowLifecycleProvider().snapshot(admitting: [])
        checks["lifecycleStoppedSnapshotHasNoHistory"] = !stopped.available
        firstLease.start()
        var restarted = await catalog.snapshot(processIDs: [pid])
        let afterStopID = ids(folder)["afterStop"]
        checks["lifecycleRestartUsesNewSessionWithoutInventedHistory"] = await waitUntil {
            restarted = await catalog.snapshot(processIDs: [pid])
            return restarted.lifecycle.available && restarted.lifecycle.sessionID != oldSession && afterStopID != nil
                && restarted.windows.contains { $0.windowID == afterStopID }
                && restarted.windows.first { $0.windowID == afterStopID }?.creationObservation == nil
        }
        firstLease.stop()
        try command("exit", folder: folder)
        checks["lifecycleOwnedProducerExitsCleanly"] = await waitUntil { !process.isRunning }
        return ["source": "production-WindowServer-observer-and-owned-child-process", "directory": folder.lastPathComponent,
                "processID": pid, "seedID": seedID, "firstID": firstID, "secondID": secondID,
                "firstSequence": firstEntry?.creationObservation?.sequence ?? 0,
                "secondSequence": fresh.windows.first { $0.windowID == secondID }?.creationObservation?.sequence ?? 0,
                "birthResolutionTrace": birthTrace,"releasedFirstState": state(folder), "extraResolutionTrace": extraTrace,
                "externalUnownedApplicationsVerified": false, "physicalHotkeysVerified": false]
    }
    private static func waitUntil(_ predicate: @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(4)
        repeat {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(30))
        } while Date() < deadline
        return false
    }
    private static func firstEntryID(_ report: WindowCatalogReport, windowID: UInt32) -> String? {
        report.windows.first { $0.windowID == windowID }?.id
    }
    private static func command(_ value: String, folder: URL) throws { try Data().write(to: folder.appendingPathComponent(value), options: .atomic) }
    private static func state(_ folder: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    private static func ids(_ folder: URL) -> [String: UInt32] {
        let values = state(folder)["ids"] as? [String: NSNumber] ?? [:]
        return values.mapValues(\.uint32Value)
    }
    private static func rawWindowExists(_ id: UInt32, pid: Int32) -> Bool {
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        return rows.contains { $0[kCGWindowNumber as String] as? UInt32 == id && $0[kCGWindowOwnerPID as String] as? Int32 == pid }
    }
}

private actor LifecycleSpaceGate: WindowSpaceProviding {
    private var armed = false
    private var pending: CheckedContinuation<Void, Never>?
    var waiting: Bool { pending != nil }
    func arm() { armed = true }
    func release() { pending?.resume(); pending = nil }
    func snapshot(windowIDs: [UInt32]) async -> WindowSpaceSnapshot {
        if armed { armed = false; await withCheckedContinuation { pending = $0 } }
        return await WindowSpaceProvider.shared.snapshot(windowIDs: windowIDs)
    }
}
#endif
