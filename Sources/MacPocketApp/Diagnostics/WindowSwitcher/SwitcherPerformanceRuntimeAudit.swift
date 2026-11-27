#if DEBUG
import AppKit
import MacPocketCore

private actor PerformancePreviewProvider: WindowPreviewCapturing {
    private let provider = WindowPreviewProvider()
    private(set) var completed: [String:TimeInterval] = [:]
    private(set) var requests = 0
    func image(for window: SwitchableWindow,maxPixels: CGSize) async throws -> WindowImage {
        requests += 1
        let image = try await provider.image(for: window,maxPixels: maxPixels)
        completed[window.id] = ProcessInfo.processInfo.systemUptime
        return image
    }
}

/// Timings separate real scoped AX/SCK and native panel work from synthetic projection load.
/// No global keyboard registration, user settings edits, focus commits or physical input.
@MainActor enum SwitcherPerformanceRuntimeAudit {
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private static func wait(_ predicate: () async -> Bool) async -> Bool {
        let deadline = now+5
        while now < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await predicate()
    }
    static func run(catalog: any WindowCatalogServing,checks: inout [String:Bool]) async throws -> [String:Any] {
        // Read-only whole-system inventories: persist counts/timings, never user window titles.
        let globalCatalog = WindowCatalog()
        var globalScans: [[String:Any]] = []
        for _ in 0..<6 {
            let start = now,report = await globalCatalog.snapshot()
            globalScans.append(["durationMs":(now-start)*1000,"windows":report.windows.count,
                "partial":report.partial,"accessibilityGranted":report.accessibilityGranted])
        }
        var scans: [Double] = []
        for _ in 0..<12 {
            let start = now,report = await catalog.snapshot()
            scans.append((now-start)*1000)
            let valid = report.windows.count == 2 && report.windows.allSatisfy { $0.windowAccessible && $0.windowID != nil }
            checks["performanceScopedCatalogHasTwoRealWindows"] = (checks["performanceScopedCatalogHasTwoRealWindows"] ?? true) && valid
            guard valid else { throw WindowCatalogError.expired }
        }
        let suite = "MacPocket.SwitcherPerformance."+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let previews = PerformancePreviewProvider()
        let model = WindowSwitcherModel(catalog: catalog,previews: previews,defaults: defaults)
        let controller = WindowSwitcherHotkeyController(model: model,modifierFlags: { .option },gestureSettings: defaults,shortcutSettings: defaults)
        defer { controller.stopForModule() }
        var shortcut = SwitcherShortcut.defaultOptionTab
        shortcut.presentation.style = .thumbnails
        shortcut.presentation.showThumbnails = true
        shortcut.presentation.openingDelayMilliseconds = 0
        shortcut.presentation.animateOpening = false
        shortcut.presentation.animateClosing = false
        shortcut.presentation.showBadges = false
        shortcut.presentation.previewSelected = false
        var openings: [[String:Any]] = []
        for index in 0..<8 {
            let cached = !model.thumbnails.isEmpty,start = now
            controller.beginHeldAudit(shortcut: shortcut)
            let visible = await wait { controller.auditPanel?.isVisible == true }
            let panelMs = (now-start)*1000
            let prepared = await wait { !controller.preparingForAudit && model.filtered.count == 2 }
            let preparedMs = (now-start)*1000
            let thumb = await wait { model.selected.flatMap { model.thumbnails[$0.id] } != nil }
            let availableMs = (now-start)*1000
            let fresh = await wait {
                guard let id = model.selection,let time = await previews.completed[id] else { return false }
                return time >= start
            }
            openings.append(["sample":index,"cachedThumbnailAtInvocation":cached,"panelVisibleMs":panelMs,
                "catalogPreparedMs":preparedMs,"thumbnailAvailableAfterPreparationMs":availableMs,"freshSelectedThumbnailMs":(now-start)*1000])
            checks["performanceOpening-\(index)"] = visible && prepared && thumb && fresh
            guard visible && prepared && thumb && fresh else { throw WindowPreviewError.unavailable }
            controller.dismissForAudit()
        }
        try await Task.sleep(for: .milliseconds(200))
        let closedRequests = await previews.requests
        try await Task.sleep(for: .milliseconds(1300))
        checks["performanceClosedPanelStartsNoCaptures"] = await previews.requests == closedRequests
        controller.stopForModule()
        checks["performanceStopReleasesResources"] = controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 }

        let projection = projectionLoad(defaults: defaults)
        return ["wholeSystemReadOnlyCatalog":globalScans,"catalogMs":scans,"catalogSummary":summary(scans),"openings":openings,"projectionLoad":projection,
            "openingDelayMs":0,"animationsEnabled":false,"physicalInputVerified":false,
            "scope":"two-owned-external-windows-real-AX-SCK-native-panel; synthetic-300-window-model-load",
            "timingsIncludePollingAndAppKitScheduling":true]
    }
    private static func projectionLoad(defaults: UserDefaults) -> [String:Any] {
        let rows: [SwitchableWindow] = (0..<300).map { (index: Int) -> SwitchableWindow in
            SwitchableWindow(id: "performance-\(index)",processID: Int32(index%20+100),application: "App \(index%20)",title: "Window \(300-index)",applicationURL: nil,
                minimized: false,hidden: false,fullScreen: false,frontmost: false,windowAccessible: false,canClose: false,canMinimize: false,canFullScreen: false,
                launchedAt: nil,lastFocusedAt: Date(timeIntervalSince1970: Double(index)),windowID: UInt32(index+1))
        }
        let model = WindowSwitcherModel(windows: rows,defaults: defaults,permitsCapture: { false })
        model.sessionFilter = .init()
        model.sessionOrder = .title
        model.selection = rows[150].id
        var timings: [Double] = [],checksum = 0
        for _ in 0..<10 {
            let start = now
            for _ in 0..<100 { checksum += model.filtered.count;checksum += model.selected?.id.count ?? 0 }
            timings.append((now-start)*1000)
        }
        return ["windows":300,"readsPerSample":200,"samplesMs":timings,"summary":summary(timings),"checksum":checksum,"source":"synthetic-model-only"]
    }
    private static func summary(_ values: [Double]) -> [String:Double] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [:] }
        return ["min":sorted[0],"median":sorted[sorted.count/2],"p95":sorted[min(sorted.count-1,Int(ceil(Double(sorted.count)*0.95))-1)],"max":sorted.last!]
    }
}
#endif
