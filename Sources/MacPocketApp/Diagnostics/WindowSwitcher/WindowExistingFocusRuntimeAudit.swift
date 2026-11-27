#if DEBUG
import AppKit
@preconcurrency import ApplicationServices
import Darwin
import MacPocketCore

/// Explicit focus-only acceptance against existing native/Electron windows. No captures, typing,
/// window actions, global shortcuts, normal AppState or persistent user preferences.
@MainActor enum WindowExistingFocusRuntimeAudit {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--audit-switcher-existing-focus") else { return }
        guard Bundle.main.bundleIdentifier == "com.doancan.MacPocket", args.indices.contains(index+1) else { exit(2) }
        let driver = ExistingFocusAuditDriver(destination: URL(fileURLWithPath: args[index+1]))
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = driver
        withExtendedLifetime(driver) { app.run() }
        exit(0)
    }
}

@MainActor private final class ExistingFocusAuditDriver: NSObject, NSApplicationDelegate {
    private let destination: URL
    private let previous = NSWorkspace.shared.frontmostApplication
    private let previousLaunch = NSWorkspace.shared.frontmostApplication?.launchDate
    private var previousWindow: AXUIElement?
    init(destination: URL) { self.destination = destination }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await run(); NSApp.terminate(nil) }
    }
    private func run() async {
        var checks: [String: Bool] = [:], traces: [[String: Any]] = []
        var record: [String: Any] = ["source": "bundled-CLI-production-focus-existing-native-and-Electron-applications",
            "physicalHotkeysVerified": false, "screenCaptureExercised": false, "globalHotkeysRegistered": false,
            "applicationStateStarted": false, "windowActionsAllowed": false, "windowTitlesRecorded": false]
        record["focusAcceptance"] = "selected-window-or-AXSheet-with-direct-same-process-AXParent-selected-window"
        let inputBefore = SecureKeyboardInputStatus.read()
        record["secureInputBefore"] = inputBefore.enabled
        if let pid = previous?.processIdentifier { previousWindow = focusedElement(pid) }
        let suite = "MacPocket.ExistingFocusAudit." + UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            guard AXIsProcessTrusted(), let executable = Bundle.main.executableURL,
                  let defaults = UserDefaults(suiteName: suite) else { throw WindowCatalogError.permissionRequired }
            defer { defaults.removePersistentDomain(forName: suite) }
            let bundles = ["com.googlecode.iterm2", "com.microsoft.VSCode"]
            let applications = bundles.compactMap { bundle in NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { !$0.isHidden && !$0.isTerminated } }
            guard applications.count == bundles.count else { throw WindowCatalogError.expired }
            let bindings = applications.compactMap { app -> (Int32, URL)? in app.bundleURL.map { (app.processIdentifier, $0) } }
            guard bindings.count == bundles.count else { throw WindowCatalogError.expired }
            let catalog = ExistingFocusCatalog(bindings: bindings)
            let model = WindowSwitcherModel(catalog: catalog, defaults: defaults, permitsCapture: { false })
            model.startObserving()
            defer { model.stopObserving() }
            let service = SwitcherCommandService(model: model, show: { _ in false }, hide: {}, visible: { false })
            let listener = try SwitcherCLIListener { await service.execute($0) }
            defer { listener.stop() }
            func cli(_ args: [String]) async throws -> (Int32, SwitcherCLIResponse?) {
                let start = ContinuousClock.now
                let result = try await BoundedProcess.run(executable.path, ["--switcher"] + args, timeout: 28)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let response = try? decoder.decode(SwitcherCLIResponse.self, from: Data(result.output.utf8))
                let elapsed = start.duration(to: .now).components
                let focusIDs = Dictionary(uniqueKeysWithValues: applications.map { ($0.bundleIdentifier ?? String($0.processIdentifier), self.focusedWindow($0.processIdentifier).map(Int.init) ?? -1) })
                let leafIDs = Dictionary(uniqueKeysWithValues: applications.map { app in
                    (app.bundleIdentifier ?? String(app.processIdentifier), focusedElement(app.processIdentifier).flatMap(elementWindowID).map(Int.init) ?? -1)
                })
                traces.append(["command": args, "exit": result.status, "status": response?.status ?? "", "errorCode": response?.errorCode ?? "",
                    "frontPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                    "focusedOwnerWindowIDs": focusIDs, "focusedLeafWindowIDs": leafIDs,
                    "milliseconds": Double(elapsed.seconds)*1000 + Double(elapsed.attoseconds)/1e15])
                return (result.status,response)
            }
            let listed = try await cli(["list", "--detailed"])
            let targets = listed.1?.windows ?? []
            record["initialTargets"] = targets.map { ["id": $0.id, "windowID": $0.windowID ?? 0, "processID": $0.details?.processID ?? 0,
                "bundleIdentifier": $0.details?.bundleIdentifier ?? ""] }
            checks["cliReadsBothExistingApplicationFamilies"] = listed.0 == 0 && Set(targets.compactMap { $0.details?.bundleIdentifier }) == Set(bundles)
            checks["cliListContainsOnlyVisibleActionableScopedWindows"] = !targets.isEmpty && targets.allSatisfy {
                guard let details = $0.details, let id = $0.windowID else { return false }
                return details.actionable && !details.hidden && !details.minimized && !details.fullScreen && !details.otherSpace
                    && Self.frames()[id] != nil
            }
            guard checks.values.allSatisfy({ $0 }), targets.count >= 2 else { throw WindowCatalogError.expired }
            record["targets"] = targets.map { ["id": $0.id, "windowID": $0.windowID ?? 0, "processID": $0.details?.processID ?? 0,
                "bundleIdentifier": $0.details?.bundleIdentifier ?? ""] }
            let geometry = Self.frames()
            // Alternate applications, then test any second native window in the same process.
            let ordered = bundles.flatMap { bundle in targets.filter { $0.details?.bundleIdentifier == bundle } }
            for (index, target) in (ordered + ordered.reversed()).enumerated() {
                guard let id = target.windowID, let pid = target.details?.processID,
                      Self.frames()[id] != nil, NSRunningApplication(processIdentifier: pid)?.isHidden == false else { throw WindowCatalogError.expired }
                let result = try await cli(["focus", index.isMultiple(of: 2) ? target.id : String(id)])
                let exact = await wait { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && self.focusedWindow(pid) == id }
                checks["existingFocus-\(index)-ConfirmsExactPIDAndWindow"] = result.0 == 0 && result.1?.status == "focused" && result.1?.targetID == target.id && exact
                // Stop at the first failure; never retry focus against a changing user session.
                guard checks["existingFocus-\(index)-ConfirmsExactPIDAndWindow"] == true else {
                    record["failedTargetDiagnostics"] = await catalog.diagnostics(target.id)
                    if let focused = self.focusedElement(pid) {
                        var values: [String: String] = [:]
                        for key in [kAXRoleAttribute, kAXSubroleAttribute, kAXModalAttribute, kAXMainAttribute, kAXFocusedAttribute] {
                            var value: CFTypeRef?
                            let status = AXUIElementCopyAttributeValue(focused, key as CFString, &value)
                            values[key] = status == .success ? String(describing: value!) : "status:\(status.rawValue)"
                        }
                        record["failedFocusedWindowAttributes"] = values
                        var ancestors: [[String: Any]] = []
                        var current: AXUIElement? = focused
                        for _ in 0..<8 {
                            guard let node = current else { break }
                            var role: CFTypeRef?, parent: CFTypeRef?
                            _ = AXUIElementCopyAttributeValue(node,kAXRoleAttribute as CFString,&role)
                            ancestors.append(["role": role as? String ?? "?", "windowID": elementWindowID(node).map(Int.init) ?? -1])
                            guard AXUIElementCopyAttributeValue(node,kAXParentAttribute as CFString,&parent) == .success,
                                  let parent,CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                            let next = unsafeDowncast(parent,to: AXUIElement.self)
                            if CFEqual(next,node) { break }
                            current = next
                        }
                        record["failedFocusedWindowAncestors"] = ancestors
                    }
                    throw WindowCatalogError.focusFailed
                }
                let destination = await catalog.focusDestination(target.id)
                let leaf = focusedElement(pid).flatMap(elementWindowID)
                checks["existingFocus-\(index)-DestinationUsesActuallyFocusedSurface"] = destination?.processID == pid && destination?.windowID == leaf
                for sibling in targets where sibling.details?.processID == pid && sibling.id != target.id {
                    checks["existingFocus-\(index)-RejectsSibling-\(sibling.windowID ?? 0)"] = await catalog.focusDestination(sibling.id) == nil
                }
                let fresh = await catalog.snapshot()
                checks["existingFocus-\(index)-MarksOnlyOwningWindowFrontmost"] = fresh.windows.first(where: { $0.id == target.id })?.frontmost == true
                    && fresh.windows.filter { $0.frontmost }.count == 1
            }
            let mru = try await cli(["list", "--detailed"])
            guard let target = mru.1?.windows?.dropFirst().first, let pid = target.details?.processID, let id = target.windowID else { throw WindowCatalogError.expired }
            let selected = try await cli(["focus", "--mru", "2"])
            let exact = await wait { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && self.focusedWindow(pid) == id }
            checks["existingFocusMRU2MatchesFreshListAndActualWindow"] = selected.0 == 0 && selected.1?.targetID == target.id && exact
            let beforeMissing = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let missing = try await cli(["focus", "missing-existing-focus-audit"])
            checks["missingTargetDoesNotChangeExistingApplicationFocus"] = missing.0 == 2 && missing.1?.errorCode == "not-found"
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == beforeMissing && focusedWindow(pid) == id
            let after = Self.frames()
            checks["existingFocusPreservesTargetGeometry"] = targets.allSatisfy { target in
                guard let id = target.windowID, let before = geometry[id], let end = after[id] else { return false }
                return abs(before.minX-end.minX) < 1 && abs(before.minY-end.minY) < 1 && abs(before.width-end.width) < 1 && abs(before.height-end.height) < 1
            }
            model.stopObserving()
            checks["focusAndLifecycleLeasesAreReleased"] = WindowFocusObservation.diagnosticResources.values.allSatisfy { $0 == 0 }
                && WindowLifecycleObservation.diagnosticResources.values.allSatisfy { $0 == 0 }
        } catch { record["error"] = String(describing: error) }
        if let previous, !previous.isTerminated, previous.launchDate == previousLaunch {
            previous.activate(options: [])
            if let window = previousWindow { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
            checks["restoresPreviousApplicationAndWindow"] = await wait {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == previous.processIdentifier else { return false }
                guard let original = self.previousWindow, let now = self.focusedElement(previous.processIdentifier) else { return self.previousWindow == nil }
                return CFEqual(original,now)
            }
        }
        record["secureInputAfter"] = SecureKeyboardInputStatus.read().enabled
        record["checks"] = checks
        record["traces"] = traces
        record["passed"] = record["error"] == nil && !checks.isEmpty && checks.values.allSatisfy { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted,.sortedKeys]) {
            try? data.write(to: destination.appendingPathComponent("report.json"), options: .atomic)
        }
    }
    private func focusedElement(_ pid: Int32) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func focusedWindow(_ pid: Int32) -> UInt32? {
        guard let focused = focusedElement(pid) else { return nil }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused,kAXRoleAttribute as CFString,&role) == .success else { return nil }
        if role as? String == kAXWindowRole as String { return elementWindowID(focused) }
        guard role as? String == kAXSheetRole as String else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused,kAXParentAttribute as CFString,&value) == .success,
              let value,CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let parent = unsafeDowncast(value,to: AXUIElement.self)
        var parentPID: pid_t = 0,parentRole: CFTypeRef?
        guard AXUIElementGetPid(parent,&parentPID) == .success,parentPID == pid,
              AXUIElementCopyAttributeValue(parent,kAXRoleAttribute as CFString,&parentRole) == .success,
              parentRole as? String == kAXWindowRole as String else { return nil }
        return elementWindowID(parent)
    }
    private func elementWindowID(_ window: AXUIElement) -> UInt32? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        typealias ReadID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        var id: CGWindowID = 0
        return unsafeBitCast(symbol, to: ReadID.self)(window, &id) == .success ? id : nil
    }
    fileprivate static func frames() -> [UInt32: CGRect] {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],0) as? [[String: Any]] ?? []
        return Dictionary(rows.compactMap { row -> (UInt32, CGRect)? in
            guard row[kCGWindowLayer as String] as? Int == 0, let id = row[kCGWindowNumber as String] as? UInt32,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return (id,frame)
        }, uniquingKeysWith: { first,_ in first })
    }
    private func wait(_ predicate: () async -> Bool) async -> Bool {
        let limit = ContinuousClock.now + .seconds(2)
        repeat { if await predicate() { return true }; try? await Task.sleep(for: .milliseconds(25)) } while ContinuousClock.now < limit
        return await predicate()
    }
}

/// Restricts the real catalog to at most two currently visible windows per preselected application.
/// Window actions are refused unconditionally; focus revalidates catalog PID/URL/launch identity.
private actor ExistingFocusCatalog: WindowCatalogServing {
    private let bindings: [(pid: Int32,url: URL,catalog: WindowCatalog)]
    private var admitted: [String: WindowCatalog] = [:]
    init(bindings: [(Int32, URL)]) { self.bindings = bindings.map { ($0.0,$0.1,WindowCatalog()) } }
    func snapshot() async -> WindowCatalogReport {
        let visible = await ExistingFocusAuditDriver.frames()
        var windows: [SwitchableWindow] = [], granted = true, partial = false
        var next: [String: WindowCatalog] = [:]
        for binding in bindings {
            let report = await binding.catalog.snapshot(processIDs: [binding.pid], matchingApplicationURL: binding.url)
            granted = granted && report.accessibilityGranted
            partial = partial || report.partial
            let rows = report.windows.filter {
                $0.windowAccessible && !$0.hidden && !$0.minimized && !$0.fullScreen && !$0.isOnAnotherSpace && $0.windowID.flatMap { visible[$0] } != nil
            }.sorted { ($0.windowID ?? 0) < ($1.windowID ?? 0) }.prefix(2)
            windows.append(contentsOf: rows)
            for row in rows { next[row.id] = binding.catalog }
        }
        admitted = next
        return .init(windows: windows, accessibilityGranted: granted, partial: partial)
    }
    func focus(_ id: String) async throws { guard let catalog = admitted[id] else { throw WindowCatalogError.expired }; try await catalog.focus(id) }
    func focusDestination(_ id: String) async -> WindowFocusDestination? { await admitted[id]?.focusDestination(id) }
    func perform(_ action: WindowAction, on id: String) async throws { throw WindowCatalogError.unsupported }
    func noteApplicationActivation(_ pid: Int32) async { for binding in bindings where binding.pid == pid { await binding.catalog.noteApplicationActivation(pid) } }
    func diagnostics(_ id: String) async -> [String: String] { await admitted[id]?.actionDiagnosticsForAudit(id) ?? [:] }
}
#endif
