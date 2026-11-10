import AppKit
import Synchronization
import XCTest
@testable import MacPocketCore
@testable import MacPocketApp

private actor CaptureFixture: WindowPreviewCapturing {
    let image: WindowImage
    var blockedIDs = Set<String>()
    var failures = Set<String>()
    private(set) var requests: [String] = []
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]

    init() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        image = WindowImage(cgImage: try XCTUnwrap(context.makeImage()))
    }

    func block(_ id: String) { blockedIDs.insert(id) }
    func fail(_ id: String) { failures.insert(id) }
    func recover(_ id: String) { failures.remove(id) }
    func isWaiting(_ id: String) -> Bool { pending[id] != nil }
    func release(_ id: String) { blockedIDs.remove(id); pending.removeValue(forKey: id)?.resume() }

    func image(for window: SwitchableWindow, maxPixels: CGSize) async throws -> WindowImage {
        requests.append(window.id)
        if blockedIDs.contains(window.id) { await withCheckedContinuation { pending[window.id] = $0 } }
        if failures.contains(window.id) { throw WindowPreviewError.unavailable }
        return WindowImage(cgImage: image.cgImage)
    }
}

private actor CatalogFixture: WindowCatalogServing {
    let report: WindowCatalogReport
    private(set) var snapshots = 0
    private var paused = true
    private var pending: CheckedContinuation<Void, Never>?
    init(windows: [SwitchableWindow], spaceMetadataAvailable: Bool = false, spaceMetadataPartial: Bool = false, lifecycle: WindowLifecycleSnapshot = .unavailable) {
        report = .init(windows: windows, accessibilityGranted: true, partial: false,
                       spaceMetadataAvailable: spaceMetadataAvailable, spaceMetadataPartial: spaceMetadataPartial, lifecycle: lifecycle)
    }
    func snapshot() async -> WindowCatalogReport {
        snapshots += 1
        if paused { await withCheckedContinuation { pending = $0 } }
        return report
    }
    func isWaiting() -> Bool { pending != nil }
    func release() { paused = false; pending?.resume(); pending = nil }
    func focus(_ id: String) async throws {}
    func perform(_ action: WindowAction, on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

private actor DelayedCloseCatalogFixture: WindowCatalogServing {
    let live: SwitchableWindow, ghost: SwitchableWindow
    let cancelled: Bool
    private(set) var snapshots = 0
    init(cancelled: Bool = false) {
        self.cancelled = cancelled
        live = .init(id: "closing", processID: 1, application: "Fixture", title: "Closing", applicationURL: nil,
                     minimized: false, hidden: false, fullScreen: false, frontmost: false, windowAccessible: true,
                     canClose: true, canMinimize: true, canFullScreen: true, launchedAt: nil, lastFocusedAt: nil, windowID: 1)
        ghost = .init(id: "closing", processID: 1, application: "Fixture", title: "Closing", applicationURL: nil,
                      minimized: false, hidden: false, fullScreen: false, frontmost: false, windowAccessible: false,
                      canClose: false, canMinimize: false, canFullScreen: false, launchedAt: nil, lastFocusedAt: nil, windowID: 1)
    }
    func snapshot() async -> WindowCatalogReport {
        snapshots += 1
        return .init(windows: cancelled ? [live] : (snapshots == 1 ? [ghost] : []), accessibilityGranted: true, partial: false)
    }
    func focus(_ id: String) async throws {}
    func perform(_ action: WindowAction, on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

private actor DelayedFocusCatalogFixture: WindowCatalogServing {
    private let fails: Bool
    private var pending: CheckedContinuation<Void, Never>?
    init(fails: Bool) { self.fails = fails }
    func snapshot() async -> WindowCatalogReport { .init(windows: [], accessibilityGranted: true, partial: false) }
    func focus(_ id: String) async throws {
        await withCheckedContinuation { pending = $0 }
        if fails { throw WindowCatalogError.expired }
    }
    func isWaiting() -> Bool { pending != nil }
    func release() { pending?.resume(); pending = nil }
    func perform(_ action: WindowAction, on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

private actor InvalidatedCatalogFixture: WindowCatalogServing {
    private let old: [SwitchableWindow]
    private let fresh: [SwitchableWindow]
    private var oldContinuation: CheckedContinuation<Void, Never>?
    private(set) var snapshots = 0
    init(old: [SwitchableWindow], fresh: [SwitchableWindow]) { self.old = old; self.fresh = fresh }
    func snapshot() async -> WindowCatalogReport {
        snapshots += 1
        if snapshots == 1 {
            await withCheckedContinuation { oldContinuation = $0 }
            return .init(windows: old, accessibilityGranted: false, partial: true)
        }
        return .init(windows: fresh, accessibilityGranted: true, partial: false, spaceMetadataAvailable: true)
    }
    func isWaiting() -> Bool { oldContinuation != nil }
    func releaseOld() { oldContinuation?.resume(); oldContinuation = nil }
    func focus(_ id: String) async throws {}
    func perform(_ action: WindowAction, on id: String) async throws {}
    func noteApplicationActivation(_ pid: Int32) async {}
}

@MainActor
final class WindowSwitcherModelTests: XCTestCase {
    private final class CapturePermission { var allowed = false }
    private final class RefreshSignal { var started = false }
    private final class FocusObservationFixture: WindowFocusObserving, WindowLifecycleObserving {
        var starts = 0
        var stops = 0
        func start() { starts += 1 }
        func stop() { stops += 1 }
    }
    private let size = CGSize(width: 320, height: 240)

    func testCycleNormalizesExtremeStepsBeforeArithmetic() {
        let model = WindowSwitcherModel(windows: [window(0),window(1),window(2)])
        model.selection = "w0";model.cycle(backwards: false,by: .max);XCTAssertEqual(model.selection,"w1")
        model.selection = "w0";model.cycle(backwards: false,by: .min);XCTAssertEqual(model.selection,"w1")
        model.selection = "w0";model.cycle(backwards: true,by: .min);XCTAssertEqual(model.selection,"w2")
        model.cycle(backwards: false,by: 0);XCTAssertEqual(model.selection,"w2")
        WindowSwitcherModel().cycle(backwards: true,by: .min)
    }

    private func window(_ index: Int) -> SwitchableWindow {
        .init(id: "w\(index)", processID: 1, application: "Fixture", title: "Document \(index)", applicationURL: nil,
              minimized: false, hidden: false, fullScreen: false, frontmost: false, windowAccessible: false,
              canClose: false, canMinimize: false, canFullScreen: false, launchedAt: nil, lastFocusedAt: nil,
              windowID: UInt32(index + 1))
    }

    private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func testSnapshotModeCapturesScrolledSelectionBeyondFirstPage() async throws {
        let capture = try CaptureFixture()
        let model = WindowSwitcherModel(windows: (0..<80).map(window), previews: capture, permitsCapture: { true })
        model.selection = "w0"
        model.thumbnailVisibilityChanged("w0", visible: true)
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let first = await eventually { model.thumbnails["w0"] != nil }
        XCTAssertTrue(first)
        model.thumbnailVisibilityChanged("w0", visible: false)
        model.selection = "w79"
        model.thumbnailVisibilityChanged("w79", visible: true)
        let scrolled = await eventually { model.thumbnails["w79"] != nil }
        XCTAssertTrue(scrolled)
        model.requestThumbnails()
        model.clearThumbnails()
        await worker.value
        let requested = await capture.requests
        XCTAssertEqual(requested.filter { $0 == "w0" }.count, 1)
        XCTAssertTrue(requested.contains("w79"))
    }

    /// A capture must redraw only its own card: the grid's inputs and other cards' slots stay untouched.
    @MainActor func testCaptureNotifiesOnlyItsOwnCardSlot() async throws {
        let capture = try CaptureFixture()
        await capture.fail("w1")
        let model = WindowSwitcherModel(windows: (0..<3).map(window), previews: capture, permitsCapture: { true })
        model.sessionFilter = .init()
        model.selection = "w0"
        let slots = (0..<3).map { model.thumbnailSlot(for: "w\($0)") }
        let notified = Mutex<Set<String>>([])
        func track(_ name: String, _ read: @escaping @MainActor () -> Void) {
            withObservationTracking { read() } onChange: { notified.withLock { _ = $0.insert(name) } }
        }
        track("grid") { _ = model.filtered; _ = model.selection; _ = model.actionBusy; _ = model.applicationBadges }
        for (index, slot) in slots.enumerated() { track("w\(index)") { _ = slot.image; _ = slot.unavailable } }
        for index in 0..<2 { model.thumbnailVisibilityChanged("w\(index)", visible: true) }
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let done = await eventually { slots[0].image != nil && slots[1].unavailable }
        XCTAssertTrue(done)
        model.clearThumbnails()
        await worker.value
        XCTAssertTrue(slots[0].image === model.thumbnails["w0"])
        XCTAssertEqual(notified.withLock { $0 }.intersection(["grid", "w2"]), [], "capture must not invalidate the grid or other cards")
        XCTAssertEqual(notified.withLock { $0 }.intersection(["w0", "w1"]), ["w0", "w1"])
    }

    func testCancelledFocusCannotClearOrReplaceNewSessionFailure() async {
        for fails in [false, true] {
            let catalog = DelayedFocusCatalogFixture(fails: fails)
            let model = WindowSwitcherModel(windows: [window(0)], catalog: catalog, permitsCapture: { false })
            let task = Task { await model.focus(id: "w0") }
            let waiting = await eventually { await catalog.isWaiting() }
            XCTAssertTrue(waiting)
            task.cancel()
            model.failure = "new-session-failure"
            await catalog.release()
            _ = await task.value
            XCTAssertEqual(model.failure, "new-session-failure", "late focus result: fails=\(fails)")
        }
    }

    func testCloseReconcilesServerBackingAfterAXWindowDisappearsWithoutHoldingActionLock() async {
        let catalog = DelayedCloseCatalogFixture()
        let model = WindowSwitcherModel(catalog: catalog, permitsCapture: { false })
        await model.action(.close, id: "closing")
        XCTAssertFalse(model.actionBusy)
        XCTAssertTrue(model.windows.contains { $0.id == "closing" })
        let removed = await eventually { model.windows.isEmpty }
        XCTAssertTrue(removed)
        XCTAssertNil(model.failure)
        model.stopObserving()
    }

    func testStopCancelsPendingCloseReconciliationBeforeAnotherCatalogRead() async {
        let catalog = DelayedCloseCatalogFixture()
        let model = WindowSwitcherModel(catalog: catalog, permitsCapture: { false })
        await model.action(.close, id: "closing")
        let before = await catalog.snapshots
        model.stopObserving()
        try? await Task.sleep(for: .milliseconds(300))
        let after = await catalog.snapshots
        XCTAssertEqual(after, before)
    }

    func testCancelledCloseThatKeepsAXWindowDoesNotStartServerBackingReconciliation() async {
        let catalog = DelayedCloseCatalogFixture(cancelled: true)
        let model = WindowSwitcherModel(catalog: catalog, permitsCapture: { false })
        await model.action(.close, id: "closing")
        try? await Task.sleep(for: .milliseconds(300))
        let reads = await catalog.snapshots
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(model.windows.first?.windowAccessible == true)
        model.stopObserving()
    }

    func testEndingSessionRejectsInFlightCapture() async throws {
        let capture = try CaptureFixture()
        await capture.block("w0")
        let model = WindowSwitcherModel(windows: [window(0)], previews: capture, permitsCapture: { true })
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let waiting = await eventually { await capture.isWaiting("w0") }
        XCTAssertTrue(waiting)
        model.clearThumbnails()
        await capture.release("w0")
        await worker.value
        XCTAssertTrue(model.thumbnails.isEmpty)
    }

    func testClosedWindowCannotRepopulateThumbnailCacheAfterRefresh() async throws {
        let capture = try CaptureFixture()
        await capture.block("w0")
        await capture.block("w1")
        let catalog = CatalogFixture(windows: [window(1)])
        await catalog.release()
        let model = WindowSwitcherModel(windows: [window(0)],catalog: catalog,previews: capture,permitsCapture: { true })
        let worker = Task { await model.runThumbnails(maxPixels: size,live: false) }
        let waiting = await eventually { await capture.isWaiting("w0") }
        XCTAssertTrue(waiting)
        await model.refresh()
        await capture.release("w0")
        model.requestThumbnails()
        // The next capture starts after the old reply was processed, without session cleanup.
        let nextCapture = await eventually { await capture.isWaiting("w1") }
        XCTAssertTrue(nextCapture)
        XCTAssertNil(model.thumbnails["w0"])
        model.clearThumbnails()
        await capture.release("w1")
        await worker.value
    }

    func testPermissionRevokedDuringSelectedPreviewRejectsLateImage() async throws {
        let capture = try CaptureFixture(),permission = CapturePermission()
        permission.allowed = true
        await capture.block("w0")
        let model = WindowSwitcherModel(windows: [window(0)],previews: capture,permitsCapture: { permission.allowed })
        model.selection = "w0"
        let task = Task { await model.loadSelectedPreview(maxPixels: size) }
        let waiting = await eventually { await capture.isWaiting("w0") }
        XCTAssertTrue(waiting)
        permission.allowed = false
        await capture.release("w0")
        await task.value
        XCTAssertNil(model.selectedPreview)
    }

    func testClosingToolsRejectsInFlightDetailPreview() async throws {
        let capture = try CaptureFixture()
        await capture.block("w0")
        let model = WindowSwitcherModel(windows: [window(0)],previews: capture,permitsCapture: { true })
        model.selection = "w0"
        let task = Task { await model.capturePreview() }
        let waiting = await eventually { await capture.isWaiting("w0") }
        XCTAssertTrue(waiting)
        model.stopObserving()
        await capture.release("w0")
        await task.value
        XCTAssertNil(model.preview)
    }

    func testOnlyFourCapturesRunAndDismissalDoesNotStartQueuedWindows() async throws {
        let capture = try CaptureFixture()
        for index in 0..<4 { await capture.block("w\(index)") }
        let model = WindowSwitcherModel(windows: (0..<20).map(window), previews: capture, permitsCapture: { true })
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let waiting = await eventually {
            for index in 0..<4 { if !(await capture.isWaiting("w\(index)")) { return false } }
            return true
        }
        XCTAssertTrue(waiting)
        let inFlight = await capture.requests
        XCTAssertEqual(inFlight.count, 4)
        model.clearThumbnails()
        for index in 0..<4 { await capture.release("w\(index)") }
        await worker.value
        let finished = await capture.requests
        XCTAssertEqual(finished.count, 4)
        XCTAssertTrue(model.thumbnails.isEmpty)
    }

    func testSelectionChangeJumpsAheadOfSlowBatch() async throws {
        let capture = try CaptureFixture()
        for index in [0, 1, 2, 3, 79] { await capture.block("w\(index)") }
        let model = WindowSwitcherModel(windows: (0..<80).map(window), previews: capture, permitsCapture: { true })
        model.selection = "w0"
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let started = await eventually {
            for index in 0..<4 { if !(await capture.isWaiting("w\(index)")) { return false } }
            return true
        }
        XCTAssertTrue(started)
        model.selection = "w79"
        model.requestThumbnails()
        await capture.release("w1")
        let priority = await eventually { await capture.isWaiting("w79") }
        XCTAssertTrue(priority)
        let requests = await capture.requests
        XCTAssertEqual(requests.count, 5)
        model.clearThumbnails()
        for index in [0, 2, 3, 79] { await capture.release("w\(index)") }
        await worker.value
    }

    func testNewPreviewNeverRetainsPreviousTargetAndRejectsLateResult() async throws {
        let capture = try CaptureFixture()
        let model = WindowSwitcherModel(windows: [window(0), window(1)], previews: capture, permitsCapture: { true })
        model.selection = "w0"
        await model.loadSelectedPreview(maxPixels: size)
        XCTAssertEqual(model.selectedPreview?.id, "w0")
        await capture.block("w1")
        model.selection = "w1"
        let request = Task { await model.loadSelectedPreview(maxPixels: size) }
        let waiting = await eventually { await capture.isWaiting("w1") }
        XCTAssertTrue(waiting)
        XCTAssertNil(model.selectedPreview)
        model.selection = "w0"
        await model.loadSelectedPreview(maxPixels: size)
        await capture.release("w1")
        await request.value
        XCTAssertEqual(model.selectedPreview?.id, "w0")
    }

    func testCaptureFailureIsVisibleAndRecoversOnNextRequest() async throws {
        let capture = try CaptureFixture()
        await capture.fail("w0")
        let model = WindowSwitcherModel(windows: [window(0)], previews: capture, permitsCapture: { true })
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let failed = await eventually { model.unavailableThumbnails.contains("w0") }
        XCTAssertTrue(failed)
        XCTAssertNil(model.thumbnails["w0"])
        await capture.recover("w0")
        model.requestThumbnails()
        let recovered = await eventually { model.thumbnails["w0"] != nil }
        XCTAssertTrue(recovered)
        XCTAssertFalse(model.unavailableThumbnails.contains("w0"))
        model.clearThumbnails()
        await worker.value
    }

    func testLargeViewportDrainsMultipleBatchesInSnapshotMode() async throws {
        let capture = try CaptureFixture()
        let model = WindowSwitcherModel(windows: (0..<80).map(window), previews: capture, permitsCapture: { true })
        for index in 0..<80 { model.thumbnailVisibilityChanged("w\(index)", visible: true) }
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let allCaptured = await eventually { model.thumbnails.count == 80 }
        XCTAssertTrue(allCaptured)
        model.clearThumbnails()
        await worker.value
        let requested = await capture.requests
        XCTAssertEqual(requested.count, 80)
    }

    func testPermissionDenialDoesNotCaptureAndRevocationClearsImages() async throws {
        let capture = try CaptureFixture()
        let permission = CapturePermission()
        let model = WindowSwitcherModel(windows: [window(0)], previews: capture, permitsCapture: { permission.allowed })
        await model.runThumbnails(maxPixels: size, live: false)
        let deniedRequests = await capture.requests
        XCTAssertTrue(deniedRequests.isEmpty)
        permission.allowed = true
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let captured = await eventually { model.thumbnails["w0"] != nil }
        XCTAssertTrue(captured)
        permission.allowed = false
        model.requestThumbnails()
        await worker.value
        XCTAssertTrue(model.thumbnails.isEmpty)
    }

    func testCacheEvictsOldPageAndCanRecaptureItInSnapshotMode() async throws {
        let capture = try CaptureFixture()
        let model = WindowSwitcherModel(windows: (0..<3).map(window), previews: capture, thumbnailCacheBudget: 256,
                                        permitsCapture: { true })
        model.selection = "w0"
        model.thumbnailVisibilityChanged("w0", visible: true)
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let first = await eventually { model.thumbnails["w0"] != nil }
        XCTAssertTrue(first)
        model.thumbnailVisibilityChanged("w0", visible: false)
        model.selection = "w2"
        model.thumbnailVisibilityChanged("w2", visible: true)
        let second = await eventually { model.thumbnails["w2"] != nil }
        XCTAssertTrue(second)
        XCTAssertNil(model.thumbnails["w0"])
        model.thumbnailVisibilityChanged("w2", visible: false)
        model.selection = "w0"
        model.thumbnailVisibilityChanged("w0", visible: true)
        let returned = await eventually { model.thumbnails["w0"] != nil }
        XCTAssertTrue(returned)
        model.clearThumbnails()
        await worker.value
        let requests = await capture.requests
        XCTAssertEqual(requests.filter { $0 == "w0" }.count, 2)
    }

    func testEvictionDoesNotCreateAnEndlessFallbackCaptureLoop() async throws {
        let capture = try CaptureFixture()
        let model = WindowSwitcherModel(windows: (0..<80).map(window), previews: capture, thumbnailCacheBudget: 256,
                                        permitsCapture: { true })
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let drained = await eventually { await capture.requests.count >= 80 }
        XCTAssertTrue(drained)
        // A demand after the first pass may recapture evicted entries once, but must not restart
        // itself indefinitely merely because those entries no longer occupy the cache.
        model.clearThumbnails()
        await worker.value
        let requests = await capture.requests
        XCTAssertEqual(requests.count, 80)
    }

    func testOldPanelVisibilityCallbacksCannotChangeNewSessionViewport() async throws {
        let capture = try CaptureFixture()
        let model = WindowSwitcherModel(windows: [window(0), window(1)], previews: capture, permitsCapture: { true })
        let oldSession = model.thumbnailSessionID
        model.clearThumbnails()
        model.thumbnailVisibilityChanged("w0", visible: true, sessionID: model.thumbnailSessionID)
        model.thumbnailVisibilityChanged("w0", visible: false, sessionID: oldSession)
        model.thumbnailVisibilityChanged("w1", visible: true, sessionID: oldSession)
        let worker = Task { await model.runThumbnails(maxPixels: size, live: false) }
        let captured = await eventually { model.thumbnails["w0"] != nil }
        XCTAssertTrue(captured)
        model.clearThumbnails()
        await worker.value
        let requests = await capture.requests
        XCTAssertEqual(requests, ["w0"])
    }

    func testNewSessionCanJoinRefreshAfterOldCallerIsCancelled() async {
        let catalog = CatalogFixture(windows: [window(1)])
        let model = WindowSwitcherModel(catalog: catalog)
        let first = Task { await model.refresh() }
        let waiting = await eventually { await catalog.isWaiting() }
        XCTAssertTrue(waiting)
        let signal = RefreshSignal()
        let second = Task { signal.started = true; await model.refresh() }
        let joined = await eventually { signal.started }
        XCTAssertTrue(joined)
        first.cancel()
        await catalog.release()
        await first.value; await second.value
        let count = await catalog.snapshots
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.windows.map(\.id), ["w1"])
        XCTAssertFalse(model.busy)
    }

    func testStoppingModuleRejectsPendingCatalogAndReleasesBusyState() async {
        let catalog = CatalogFixture(windows: [window(1)])
        let model = WindowSwitcherModel(windows: [window(0)], catalog: catalog)
        let task = Task { await model.refresh() }
        let waiting = await eventually { await catalog.isWaiting() }
        XCTAssertTrue(waiting)
        model.stopObserving()
        await catalog.release(); await task.value
        XCTAssertEqual(model.windows.map(\.id), ["w0"])
        XCTAssertNil(model.lastRefresh)
        XCTAssertFalse(model.busy)
    }

    func testRefreshPreservesSelectionMadeWhileWaiting() async {
        let catalog = CatalogFixture(windows: [window(0), window(1)])
        let model = WindowSwitcherModel(windows: [window(0), window(1)], catalog: catalog)
        model.selection = "w0"
        let task = Task { await model.refresh() }
        let waiting = await eventually { await catalog.isWaiting() }
        XCTAssertTrue(waiting)
        model.selection = "w1"
        await catalog.release(); await task.value
        XCTAssertEqual(model.selection, "w1")
    }

    func testSessionSortAndSearchStateAreIndependentFromGlobalSettings() {
        let model = WindowSwitcherModel(windows: [window(1), window(0)])
        model.sessionFilter = .init()
        model.sessionOrder = .title
        XCTAssertEqual(model.filtered.map(\.id), ["w0", "w1"])
        model.sessionOrder = .application
        XCTAssertEqual(model.filtered.map(\.id), ["w1", "w0"])
        model.beginSearch(); model.sessionSearch = "a"; model.sessionSearch = ""
        XCTAssertTrue(model.isSearching)
        model.resetSessionSearch()
        XCTAssertFalse(model.isSearching)
    }

    func testRecorderAdmissionIsExclusiveAndModuleStopReleasesIt() {
        let controller = WindowSwitcherHotkeyController()
        XCTAssertTrue(controller.setRecording(true))
        XCTAssertFalse(controller.setRecording(true))
        XCTAssertTrue(controller.recordingShortcut)
        controller.stopForModule()
        XCTAssertFalse(controller.recordingShortcut)
        XCTAssertTrue(controller.setRecording(true))
        controller.setRecording(false)
        XCTAssertTrue(controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 })
    }

    func testPointerScopeIsCapturedBeforePanelAndDoesNotFollowMouseOrReorderedWindows() async {
        func placed(_ index: Int, pid: Int32, z: Int) -> SwitchableWindow {
            .init(id: "pointer-\(index)", processID: pid, application: "Fixture \(pid)", title: "Document \(index)", applicationURL: nil,
                  minimized: false, hidden: false, fullScreen: false, frontmost: false, windowAccessible: true,
                  canClose: true, canMinimize: true, canFullScreen: true, launchedAt: nil, lastFocusedAt: nil,
                  windowID: UInt32(index + 1), frame: CGRect(x: -100, y: 20, width: 80, height: 80), zOrder: z)
        }
        let cached = [placed(0, pid: 1, z: 0), placed(1, pid: 2, z: 1)]
        let fresh = [placed(0, pid: 1, z: 1), placed(1, pid: 2, z: 0)]
        let catalog = CatalogFixture(windows: fresh)
        await catalog.release()
        let model = WindowSwitcherModel(windows: cached, catalog: catalog)
        var filter = WindowListFilter(); filter.applicationScope = .pointerApplication
        model.sessionFilter = filter
        model.captureSessionPointer(at: CGPoint(x: -50, y: 50))
        XCTAssertEqual(model.filtered.map(\.id), ["pointer-0"])
        await model.refresh()
        XCTAssertEqual(model.sessionPointerApplicationPID, 1)
        XCTAssertEqual(model.filtered.map(\.id), ["pointer-0"])
        model.captureSessionPointer(at: nil)
        XCTAssertTrue(model.filtered.isEmpty)
        model.captureSessionPointer(at: CGPoint(x: -50, y: 50))
        XCTAssertEqual(model.filtered.map(\.id), ["pointer-1"])

        let coldModel = WindowSwitcherModel(catalog: catalog)
        coldModel.sessionFilter = filter
        coldModel.captureSessionPointer(at: CGPoint(x: -50, y: 50))
        XCTAssertTrue(coldModel.filtered.isEmpty)
        await coldModel.refresh()
        XCTAssertEqual(coldModel.sessionPointerApplicationPID, 2)
        XCTAssertEqual(coldModel.filtered.map(\.id), ["pointer-1"])
    }

    func testFilteringAndGroupingKeepKeyboardCycleInsideEligibleWindows() {
        let model = WindowSwitcherModel(windows: [window(0), window(1), window(2)])
        var filter = WindowListFilter(); filter.grouping = .onePerApplication
        model.sessionFilter = filter
        model.selection = "w0"
        model.cycle(backwards: false)
        XCTAssertEqual(model.selection, "w0")
        model.sessionSearch = "Document 2"
        XCTAssertEqual(model.filtered.map(\.id), ["w2"])
        model.cycle(backwards: false)
        XCTAssertEqual(model.selection, "w2")
        filter.applicationScope = .other; model.foregroundPID = 1; model.sessionFilter = filter
        XCTAssertTrue(model.filtered.isEmpty)
        model.cycle(backwards: false)
        XCTAssertNil(model.selected)
    }

    func testFocusObservationLeaseStartsOnceAndStopsWithTheModel() {
        let observer = FocusObservationFixture()
        let lifecycle = FocusObservationFixture()
        let model = WindowSwitcherModel(focusObservation: observer, lifecycleObservation: lifecycle)
        model.startObserving(); model.startObserving()
        XCTAssertEqual(observer.starts, 1)
        model.stopObserving()
        XCTAssertEqual(observer.stops, 1)
        model.startObserving()
        XCTAssertEqual(observer.starts, 2)
        model.stopObserving()
        XCTAssertEqual(observer.stops, 2)
        XCTAssertEqual(lifecycle.starts, 2); XCTAssertEqual(lifecycle.stops, 2)
    }

    func testLifecycleNotificationRemovesDestroyedWindowWithoutStartingClosedPanelScan() async {
        var timeline = WindowLifecycleTimeline()
        let catalog = CatalogFixture(windows: [window(0), window(1)], lifecycle: timeline.snapshot)
        await catalog.release()
        let lifecycle = FocusObservationFixture()
        let model = WindowSwitcherModel(catalog: catalog, focusObservation: FocusObservationFixture(), lifecycleObservation: lifecycle)
        model.startObserving(); defer { model.stopObserving() }
        await model.refresh()
        timeline.record(.init(event: .destroyed, windowID: 1), at: .now)
        NotificationCenter.default.post(name: WindowLifecycleObservation.didChangeNotification, object: nil,
            userInfo: [WindowLifecycleObservation.snapshotKey: timeline.snapshot])
        XCTAssertEqual(model.windows.map(\.id), ["w1"])
        XCTAssertEqual(model.lifecycleRevision, 1)
        let snapshots = await catalog.snapshots
        XCTAssertEqual(snapshots, 1)
        XCTAssertFalse(model.busy)
    }

    func testDestroyedNativeAnchorAlsoRemovesItsWindowlessBackgroundTabCards() async {
        var timeline = WindowLifecycleTimeline()
        var anchor = window(0), background = window(1)
        anchor.nativeTab = .init(groupID: "owned-group", controlID: "a", ordinal: 1, count: 2, selected: true)
        background.windowID = nil
        background.nativeTab = .init(groupID: "owned-group", controlID: "b", ordinal: 2, count: 2, selected: false)
        let catalog = CatalogFixture(windows: [anchor, background, window(2)], lifecycle: timeline.snapshot)
        await catalog.release()
        let model = WindowSwitcherModel(catalog: catalog, focusObservation: FocusObservationFixture(), lifecycleObservation: FocusObservationFixture())
        model.startObserving(); defer { model.stopObserving() }
        await model.refresh()
        timeline.record(.init(event: .destroyed, windowID: 1), at: .now)
        NotificationCenter.default.post(name: WindowLifecycleObservation.didChangeNotification, object: nil,
            userInfo: [WindowLifecycleObservation.snapshotKey: timeline.snapshot])
        XCTAssertEqual(model.windows.map(\.id), ["w2"])
    }

    func testFreshSpaceMembershipUpdatesFiltersAndIndependentSessionOrder() async {
        var first = window(0), second = window(1)
        first.spaceMembership = .init(spaces: [.init(id: 11, ordinal: 1, displayIdentifier: "A", kind: .desktop, visible: true)])
        second.spaceMembership = .init(spaces: [.init(id: 12, ordinal: 2, displayIdentifier: "A", kind: .desktop, visible: false)])
        let catalog = CatalogFixture(windows: [second, first], spaceMetadataAvailable: true, spaceMetadataPartial: true)
        await catalog.release()
        let model = WindowSwitcherModel(catalog: catalog)
        let originalOrder = model.order
        var filter = WindowListFilter(); filter.spaceScope = .notVisible
        model.sessionFilter = filter; model.sessionOrder = .space
        await model.refresh()
        XCTAssertTrue(model.spaceMetadataAvailable); XCTAssertTrue(model.spaceMetadataPartial)
        XCTAssertEqual(model.filtered.map(\.id), ["w1"])
        filter.spaceScope = .all; model.sessionFilter = filter
        XCTAssertEqual(model.filtered.map(\.id), ["w0", "w1"])
        model.sessionFilter = nil
        XCTAssertEqual(model.order, originalOrder, "A session override must not change the saved global order")
    }

    func testEnvironmentInvalidationStartsFreshScanAndRejectsLateOldMetadata() async {
        let catalog = InvalidatedCatalogFixture(old: [window(0)], fresh: [window(1)])
        let model = WindowSwitcherModel(windows: [window(0)], catalog: catalog)
        let oldTask = Task { await model.refresh() }
        let waiting = await eventually { await catalog.isWaiting() }
        XCTAssertTrue(waiting)
        model.invalidateSnapshot()
        await model.refresh()
        XCTAssertEqual(model.windows.map(\.id), ["w1"])
        XCTAssertTrue(model.trusted); XCTAssertTrue(model.spaceMetadataAvailable); XCTAssertFalse(model.partial)
        await catalog.releaseOld(); await oldTask.value
        XCTAssertEqual(model.windows.map(\.id), ["w1"])
        XCTAssertTrue(model.trusted); XCTAssertTrue(model.spaceMetadataAvailable); XCTAssertFalse(model.busy)
        let scans = await catalog.snapshots
        XCTAssertEqual(scans, 2)
    }

    func testStoppingModuleCancelsDelayedPrewarmBeforeItStartsAScan() async {
        let catalog = CatalogFixture(windows: [window(0)])
        let model = WindowSwitcherModel(catalog: catalog)
        let controller = WindowSwitcherHotkeyController(model: model)
        controller.schedulePrewarmForAudit(delay: .milliseconds(80))
        controller.stopForModule()
        try? await Task.sleep(for: .milliseconds(120))
        let count = await catalog.snapshots
        XCTAssertEqual(count, 0)
        XCTAssertTrue(controller.moduleDiagnosticResources.values.allSatisfy { $0 == 0 })
    }
}
