import AppKit
import Combine
import MacPocketCore
import SwiftUI

/// One card's image state. Cards observe their own slot, so a capture redraws that card only
/// instead of invalidating the grid and every other card.
@MainActor
@Observable
final class SwitcherThumbnailSlot {
    fileprivate(set) var image: NSImage?
    fileprivate(set) var unavailable = false
}

/// Shared window list for the keyboard switcher and the Tools detail table.
@MainActor
@Observable
final class WindowSwitcherModel {
    private(set) var windows: [SwitchableWindow] = [] { didSet { filteredCache = nil } }
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var partial = false
    private(set) var otherSpacesVisible = false
    private(set) var spaceMetadataAvailable = false
    private(set) var spaceMetadataPartial = false
    private(set) var busy = false
    private(set) var actionBusy = false
    var failure: String?
    var selection: String?
    /// Table search in Tools.
    var search = "" { didSet { filteredCache = nil } }
    /// Type-to-search inside the switcher panel.
    var sessionSearch = "" { didSet { filteredCache = nil } }
    private(set) var isSearching = false
    /// Live thumbnails keyed by window id; only populated while the switcher is open. Views read
    /// `thumbnailSlot(for:)` instead, so these two are not observed directly.
    @ObservationIgnored private(set) var thumbnails: [String: NSImage] = [:] {
        didSet { for (id, slot) in thumbnailSlots where slot.image !== thumbnails[id] { slot.image = thumbnails[id] } }
    }
    @ObservationIgnored private(set) var unavailableThumbnails = Set<String>() {
        didSet {
            for (id, slot) in thumbnailSlots {
                let unavailable = unavailableThumbnails.contains(id)
                if slot.unavailable != unavailable { slot.unavailable = unavailable }
            }
        }
    }
    @ObservationIgnored private var thumbnailSlots: [String: SwitcherThumbnailSlot] = [:]
    /// Application-owned Dock values, populated only while the HUD is visible.
    private(set) var applicationBadges: [DockBadgeTarget: DockApplicationBadge] = [:]
    /// Large image of the selected window for the in-place preview.
    private(set) var selectedPreview: (id: String, image: NSImage)?
    var preview: NSImage?
    var previewBusy = false
    var previewMessage: String?
    private(set) var lastRefresh: Date?

    private(set) var lifecycleRevision: UInt64 = 0
    @ObservationIgnored private var appliedLifecycle: WindowLifecycleSnapshot = .unavailable

    var foregroundPID: Int32? { didSet { filteredCache = nil } }
    /// Non-nil while a switcher session runs; it replaces the table filters.
    var sessionFilter: WindowListFilter? { didSet { filteredCache = nil } }
    var sessionDisplayID: UInt32? { didSet { filteredCache = nil } }
    var sessionOrder: WindowSortOrder? { didSet { filteredCache = nil } }
    private(set) var sessionPointerLocation: CGPoint? { didSet { filteredCache = nil } }
    private(set) var sessionPointerApplicationPID: Int32? { didSet { filteredCache = nil } }
    private(set) var exceptionRules: [SwitcherExceptionRule] { didSet { filteredCache = nil } }
    /// Selection, image and badge updates reuse the same projection. Its inputs invalidate the
    /// cache above; effective defaults ordering and locale are checked on read as they can change
    /// outside this object. One bounded value array is retained, never AX handles or images.
    @ObservationIgnored private var filteredCache: (order: WindowSortOrder,locale: String,windows: [SwitchableWindow])?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let badgeReader: any DockApplicationBadgeReading
    @ObservationIgnored private var badgeSessionID: UUID?
    @ObservationIgnored private var badgeWorkerID: UUID?
    @ObservationIgnored private let cursorFollower: any WindowCursorFollowing
    @ObservationIgnored private var focusGeneration = UUID()
    @ObservationIgnored private var exceptionObserver: AnyCancellable?
    @ObservationIgnored private let catalog: any WindowCatalogServing
    @ObservationIgnored private let focusObservation: any WindowFocusObserving
    @ObservationIgnored private let lifecycleObservation: any WindowLifecycleObserving
    @ObservationIgnored private let previews: any WindowPreviewCapturing
    @ObservationIgnored private let permitsCapture: @MainActor () -> Bool
    @ObservationIgnored private var activationObserver: AnyCancellable?
    @ObservationIgnored private var lifecycleObserver: AnyCancellable?
    @ObservationIgnored private var refreshTask: Task<WindowCatalogReport, Never>?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var appliedRefreshID: UUID?
    @ObservationIgnored private var thumbnailGeneration = UUID()
    @ObservationIgnored private var visibleThumbnailIDs = Set<String>()
    @ObservationIgnored private var thumbnailCapturedAt: [String: Date] = [:]
    @ObservationIgnored private var thumbnailAccessedAt: [String: Date] = [:]
    @ObservationIgnored private var thumbnailCosts: [String: Int] = [:]
    @ObservationIgnored private let thumbnailCacheBudget: Int
    @ObservationIgnored private var thumbnailRequests: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var thumbnailWorkerID: UUID?
    @ObservationIgnored private var actionReconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var actionReconciliationID = UUID()
    @ObservationIgnored private var thumbnailAttemptedIDs = Set<String>()
    var thumbnailSessionID: UUID { thumbnailGeneration }

    init(windows: [SwitchableWindow] = [], catalog: any WindowCatalogServing = WindowCatalog(),
         focusObservation: any WindowFocusObserving = WindowFocusObservation(),
         lifecycleObservation: any WindowLifecycleObserving = WindowLifecycleObservation(),
         previews: any WindowPreviewCapturing = WindowPreviewProvider(),
         thumbnailCacheBudget: Int = 64 * 1024 * 1024, defaults: UserDefaults = .standard,
         cursorFollower: any WindowCursorFollowing = WindowCursorFollower(),
         badgeReader: any DockApplicationBadgeReading = DockApplicationBadgeReader(),
         permitsCapture: @escaping @MainActor () -> Bool = { WindowPreviewProvider.permitted }) {
        self.cursorFollower = cursorFollower
        self.badgeReader = badgeReader
        self.defaults = defaults
        self.exceptionRules = SwitcherExceptionStore.load(defaults).rules
        self.windows = windows
        self.catalog = catalog
        self.focusObservation = focusObservation
        self.lifecycleObservation = lifecycleObservation
        self.previews = previews
        self.thumbnailCacheBudget = max(0, thumbnailCacheBudget)
        self.permitsCapture = permitsCapture
    }

    func startObserving() {
        guard activationObserver == nil else { return }
        reloadExceptions()
        exceptionObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.reloadExceptions() } }
        focusObservation.start()
        lifecycleObservation.start()
        lifecycleObserver = NotificationCenter.default.publisher(for: WindowLifecycleObservation.didChangeNotification)
            .sink { [weak self] notification in
                guard let snapshot = notification.userInfo?[WindowLifecycleObservation.snapshotKey] as? WindowLifecycleSnapshot else { return }
                MainActor.assumeIsolated { self?.lifecycleChanged(snapshot) }
            }
        activationObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in await self?.catalog.noteApplicationActivation(pid) }
            }
    }

    func stopObserving() {
        focusGeneration = UUID()
        stopApplicationBadges()
        cancelActionReconciliation()
        focusObservation.stop()
        lifecycleObservation.stop()
        lifecycleObserver = nil
        activationObserver = nil
        exceptionObserver = nil
        invalidateSnapshot()
        clearThumbnails()
    }

    /// A Space/display notification invalidates a scan that may have begun in the old environment.
    /// Callers of that scan can finish, but its report cannot overwrite the next one.
    func invalidateSnapshot() {
        refreshTask?.cancel(); refreshTask = nil
        refreshID = UUID()
        busy = false
    }

    private func lifecycleChanged(_ snapshot: WindowLifecycleSnapshot) {
        invalidateSnapshot()
        let groups = Set(windows.filter { window in
            window.windowID.map { snapshot.invalidates($0, since: appliedLifecycle) } == true
        }.compactMap { $0.nativeTab?.groupID })
        windows.removeAll { window in
            window.windowID.map { snapshot.invalidates($0, since: appliedLifecycle) } == true
                || window.nativeTab.map { groups.contains($0.groupID) } == true
        }
        let present = Set(windows.map(\.id))
        retainThumbnails(present)
        if let selectedPreview, !present.contains(selectedPreview.id) { self.selectedPreview = nil }
        preview = nil
        lifecycleRevision &+= 1
    }

    private func retainThumbnails(_ present: Set<String>) {
        if thumbnails.keys.contains(where: { !present.contains($0) }) { thumbnails = thumbnails.filter { present.contains($0.key) } }
        thumbnailCapturedAt = thumbnailCapturedAt.filter { present.contains($0.key) }
        thumbnailAccessedAt = thumbnailAccessedAt.filter { present.contains($0.key) }
        thumbnailCosts = thumbnailCosts.filter { present.contains($0.key) }
        unavailableThumbnails.formIntersection(present)
        if thumbnailSlots.keys.contains(where: { !present.contains($0) }) { thumbnailSlots = thumbnailSlots.filter { present.contains($0.key) } }
    }

    /// Stable per-window image state for a card; created on first use with the current values.
    func thumbnailSlot(for id: String) -> SwitcherThumbnailSlot {
        if let slot = thumbnailSlots[id] { return slot }
        let slot = SwitcherThumbnailSlot()
        slot.image = thumbnails[id]; slot.unavailable = unavailableThumbnails.contains(id)
        thumbnailSlots[id] = slot
        return slot
    }

    func reloadExceptions() {
        let rules = SwitcherExceptionStore.load(defaults).rules
        if rules != exceptionRules { exceptionRules = rules }
    }

    var order: WindowSortOrder { WindowSortOrder(rawValue: defaults.string(forKey: "switcher.sort") ?? "recent") ?? .recent }

    var filtered: [SwitchableWindow] {
        let effectiveOrder = sessionFilter != nil ? (sessionOrder ?? order) : order
        let locale = Locale.current.identifier
        if let cached = filteredCache,cached.order == effectiveOrder,cached.locale == locale { return cached.windows }
        let result: [SwitchableWindow]
        if let filter = sessionFilter {
            result = WindowFiltering.apply(windows, filter: filter,
                context: .init(foregroundPID: foregroundPID, displayID: sessionDisplayID,
                               pointerLocation: sessionPointerLocation, pointerApplicationPID: sessionPointerApplicationPID),
                search: sessionSearch, order: effectiveOrder, exceptions: exceptionRules)
        } else {
            result = WindowFiltering.apply(windows, search: search, order: effectiveOrder, exceptions: exceptionRules)
        }
        filteredCache = (effectiveOrder,locale,result)
        return result
    }

    var selected: SwitchableWindow? { filtered.first { $0.id == selection } }

    func beginSearch() { if !isSearching { isSearching = true } }
    func resetSessionSearch() {
        if !sessionSearch.isEmpty { sessionSearch = "" }
        if isSearching { isSearching = false }
    }

    func captureSessionPointer(at point: CGPoint?) {
        sessionPointerLocation = point
        sessionPointerApplicationPID = WindowFiltering.applicationUnderPointer(windows, at: point)
    }

    /// A fresh CLI inventory shares observed focus history without changing the HUD/table selection.
    func commandSnapshot() async -> WindowCatalogReport { await catalog.snapshot() }

    func refresh() async {
        if foregroundPID == nil { foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let task: Task<WindowCatalogReport, Never>
        if let pending = refreshTask { task = pending }
        else {
            let pending = Task { [catalog] in await catalog.snapshot() }
            refreshTask = pending; task = pending
            refreshID = UUID()
            busy = true
        }
        let id = refreshID
        let report = await task.value
        guard id == refreshID else { return }
        refreshTask = nil; busy = false
        guard !Task.isCancelled, appliedRefreshID != id else { return }
        appliedRefreshID = id
        let old = selection
        windows = report.windows
        // A cold opening has no cached target. Resolve it once from the fresh list; after that
        // moving over the HUD or closing another window cannot switch the captured application.
        if sessionFilter != nil, sessionPointerApplicationPID == nil {
            sessionPointerApplicationPID = WindowFiltering.applicationUnderPointer(windows, at: sessionPointerLocation)
        }
        // Thumbnails outlive a session so the next one opens with images already in place.
        let present = Set(report.windows.map(\.id))
        retainThumbnails(present)
        appliedLifecycle = report.lifecycle
        // Observation notifies on every write, even of an equal value; the open HUD reads these flags.
        if trusted != report.accessibilityGranted { trusted = report.accessibilityGranted }
        if partial != report.partial { partial = report.partial }
        if otherSpacesVisible != report.otherSpacesVisible { otherSpacesVisible = report.otherSpacesVisible }
        if spaceMetadataAvailable != report.spaceMetadataAvailable { spaceMetadataAvailable = report.spaceMetadataAvailable }
        if spaceMetadataPartial != report.spaceMetadataPartial { spaceMetadataPartial = report.spaceMetadataPartial }
        lastRefresh = Date()
        if sessionFilter == nil, foregroundPID == ProcessInfo.processInfo.processIdentifier || foregroundPID == nil {
            foregroundPID = windows.first?.processID
        }
        if sessionFilter == nil { selection = filtered.contains { $0.id == old } ? old : filtered.first?.id }
    }

    func applicationBadge(for window: SwitchableWindow) -> DockApplicationBadge? {
        DockBadgeTarget(window).flatMap { applicationBadges[$0] }
    }

    @discardableResult func beginApplicationBadges() -> UUID {
        let id = UUID();badgeSessionID = id;badgeWorkerID = nil
        if !applicationBadges.isEmpty { applicationBadges = [:] }
        return id
    }
    func stopApplicationBadges() {
        badgeSessionID = nil;badgeWorkerID = nil
        if !applicationBadges.isEmpty { applicationBadges = [:] }
    }
    /// Only the visible HUD owns a polling worker. Never warms badges in the background or lets a
    /// late reply from a dismissed panel replace the next session's state.
    func runApplicationBadges(session id: UUID) async {
        guard badgeSessionID == id,badgeWorkerID == nil,!Task.isCancelled else { return }
        let worker = UUID();badgeWorkerID = worker
        defer { if badgeWorkerID == worker { badgeWorkerID = nil } }
        while badgeSessionID == id,!Task.isCancelled {
            let requested = Set(filtered.compactMap(DockBadgeTarget.init))
            let result = requested.isEmpty ? [:] : await badgeReader.badges(for: Array(requested))
            guard badgeSessionID == id,badgeWorkerID == worker,!Task.isCancelled else { return }
            let current = Set(filtered.compactMap(DockBadgeTarget.init))
            let next = result.filter { requested.contains($0.key) && current.contains($0.key) }
            if next != applicationBadges { applicationBadges = next }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    @discardableResult func focus(id: String? = nil,cursorPolicy: SwitcherCursorPolicy? = nil) async -> Bool {
        guard let target = id ?? selected?.id,!Task.isCancelled else { return false }
        let generation = UUID();focusGeneration = generation
        let policy = cursorPolicy ?? SwitcherCursorPolicy.load(defaults)
        let origin = policy == .never ? nil : cursorFollower.captureOrigin()
        do {
            try await catalog.focus(target)
            guard !Task.isCancelled,focusGeneration == generation else { return false }
            failure = nil
            if policy != .never,let origin {
                for _ in 0..<8 {
                    let destination = await catalog.focusDestination(target)
                    guard !Task.isCancelled,focusGeneration == generation else { return false }
                    if let destination {
                        let outcome = cursorFollower.follow(destination,from: origin,policy: policy)
                        if outcome != .notReady { break }
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
            }
            return true
        } catch is CancellationError { return false } catch {
            guard !Task.isCancelled,focusGeneration == generation else { return false }
            failure = error.localizedDescription
            return false
        }
    }

    func action(_ action: WindowAction, id: String? = nil) async {
        guard !actionBusy, let target = id ?? selected?.id else { return }
        cancelActionReconciliation()
        let reconciliation = actionReconciliationID
        actionBusy = true
        failure = nil
        defer { actionBusy = false }
        do {
            try await catalog.perform(action, on: target)
            failure = nil
            // Give the app a moment to apply the change before re-reading its windows.
            try? await Task.sleep(for: .milliseconds(action == .quitApplication ? 400 : 150))
            await refresh()
            if action == .close, reconciliation == actionReconciliationID,
               windows.contains(where: { $0.id == target && !$0.windowAccessible }) {
                // A closing AppKit window can remain composited after it leaves AXWindows.
                // Re-read after that animation, without holding the action lock or replaying AX.
                actionReconciliationTask = Task { [weak self] in
                    guard let self else { return }
                    defer { if actionReconciliationID == reconciliation { actionReconciliationTask = nil } }
                    for delay in [200,400,800] {
                        try? await Task.sleep(for: .milliseconds(delay))
                        guard !Task.isCancelled, actionReconciliationID == reconciliation else { return }
                        await refresh()
                        if !windows.contains(where: { $0.id == target }) { return }
                    }
                }
            }
        } catch { failure = error.localizedDescription }
    }

    func cancelActionReconciliation() {
        actionReconciliationID = UUID()
        actionReconciliationTask?.cancel(); actionReconciliationTask = nil
    }

    func cycle(backwards: Bool, by step: Int = 1) {
        let rows = filtered
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? (backwards ? 0 : -1)
        let boundedStep = step % rows.count
        let next = ((current + (backwards ? -boundedStep : boundedStep)) % rows.count + rows.count) % rows.count
        selection = rows[next].id
    }

    func moveRow(backwards: Bool, columns: Int) {
        selection = WindowSwitchSelection.applying([.row(backwards: backwards)],to: filtered,preserving: selection,columns: columns)
    }

    // MARK: Thumbnails

    func thumbnailVisibilityChanged(_ id: String, visible: Bool, sessionID: UUID? = nil) {
        guard sessionID == nil || sessionID == thumbnailGeneration else { return }
        if visible { visibleThumbnailIDs.insert(id); thumbnailAccessedAt[id] = Date() }
        else { visibleThumbnailIDs.remove(id) }
        requestThumbnails()
    }

    func requestThumbnails() {
        if let selection { thumbnailAccessedAt[selection] = Date() }
        thumbnailRequests?.yield(())
    }

    private func cacheThumbnail(_ image: WindowImage, id: String) {
        thumbnails[id] = NSImage(cgImage: image.cgImage, size: .zero)
        thumbnailCapturedAt[id] = image.capturedAt
        thumbnailAccessedAt[id] = Date()
        thumbnailCosts[id] = image.cgImage.bytesPerRow * image.cgImage.height
        var cost = thumbnailCosts.values.reduce(0, +)
        // Visible cards and selection stay available even if the viewport itself exceeds the budget.
        let evictable = thumbnailCosts.keys.filter { !visibleThumbnailIDs.contains($0) && $0 != selection }
            .sorted { (thumbnailAccessedAt[$0] ?? .distantPast) < (thumbnailAccessedAt[$1] ?? .distantPast) }
        for candidate in evictable where cost > thumbnailCacheBudget {
            cost -= thumbnailCosts.removeValue(forKey: candidate) ?? 0
            thumbnails.removeValue(forKey: candidate)
            thumbnailCapturedAt.removeValue(forKey: candidate)
            thumbnailAccessedAt.removeValue(forKey: candidate)
        }
    }

    private func needsThumbnail(_ window: SwitchableWindow, live: Bool) -> Bool {
        guard let capturedAt = thumbnailCapturedAt[window.id] else { return true }
        return live && Date().timeIntervalSince(capturedAt) >= 1
    }

    /// One serial worker owns capture batches. Selection/scroll events coalesce while a batch is in
    /// flight; they do not cancel and duplicate expensive ScreenCaptureKit requests. Captures themselves
    /// run at most four at a time. Live refreshes apply only to the current viewport and selection.
    func runThumbnails(maxPixels: CGSize, live: Bool) async {
        guard permitsCapture() else { return }
        let generation = thumbnailGeneration
        let workerID = UUID()
        thumbnailWorkerID = workerID
        let (requests, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        thumbnailRequests = continuation
        let ticker = Task {
            guard live else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
                continuation.yield(())
            }
        }
        defer {
            ticker.cancel()
            continuation.finish()
            if thumbnailWorkerID == workerID { thumbnailRequests = nil; thumbnailWorkerID = nil }
        }
        continuation.yield(())
        for await _ in requests {
            guard !Task.isCancelled, generation == thumbnailGeneration else { break }
            guard permitsCapture() else {
                thumbnails = [:]; thumbnailCapturedAt = [:]; thumbnailCosts = [:]; thumbnailAccessedAt = [:]
                break
            }
            let demand = WindowThumbnailPlan.targets(filtered, selection: selection, visibleIDs: visibleThumbnailIDs, limit: .max)
            let fillingNewCards = demand.contains { !thumbnailAttemptedIDs.contains($0.id) }
            let candidates = filtered.filter {
                needsThumbnail($0, live: live) && (!fillingNewCards || !thumbnailAttemptedIDs.contains($0.id) || $0.id == selection)
            }.sorted {
                // Uncaptured cards must not starve behind a slow refresh of earlier cards.
                let leftAttempted = thumbnailAttemptedIDs.contains($0.id), rightAttempted = thumbnailAttemptedIDs.contains($1.id)
                if leftAttempted != rightAttempted { return !leftAttempted }
                return (thumbnailCapturedAt[$0.id] ?? .distantPast) < (thumbnailCapturedAt[$1.id] ?? .distantPast)
            }
            let targets = WindowThumbnailPlan.targets(candidates, selection: selection, visibleIDs: visibleThumbnailIDs)
            await withTaskGroup(of: (String, WindowImage?).self) { group in
                var iterator = targets.makeIterator()
                var scheduled = Set<String>()
                @MainActor func nextTarget() -> SwitchableWindow? {
                    let current = filtered
                    // A key press during a slow batch jumps ahead of the remaining work as soon
                    // as a capture slot frees, including a selection outside the original batch.
                    if let selected, selected.windowID != nil, !selected.minimized,
                       !scheduled.contains(selected.id), needsThumbnail(selected, live: live) {
                        scheduled.insert(selected.id)
                        return selected
                    }
                    while let candidate = iterator.next() {
                        if !scheduled.contains(candidate.id), current.contains(where: { $0.id == candidate.id }) {
                            scheduled.insert(candidate.id)
                            return candidate
                        }
                    }
                    return nil
                }
                // Four concurrent captures keep the first pass fast without flooding ScreenCaptureKit.
                for _ in 0..<4 {
                    guard let window = nextTarget() else { break }
                    group.addTask { [previews] in (window.id, try? await previews.image(for: window, maxPixels: maxPixels)) }
                }
                for await (id, image) in group {
                    // Refresh can remove a closed target while its ScreenCaptureKit reply is pending.
                    if generation == thumbnailGeneration, !Task.isCancelled, permitsCapture(),
                       windows.contains(where: { $0.id == id }) {
                        thumbnailAttemptedIDs.insert(id)
                        if let image {
                            cacheThumbnail(image, id: id)
                            if unavailableThumbnails.contains(id) { unavailableThumbnails.remove(id) }
                        } else {
                            unavailableThumbnails.insert(id)
                        }
                    }
                    if !Task.isCancelled, generation == thumbnailGeneration, permitsCapture(), let window = nextTarget() {
                        group.addTask { [previews] in (window.id, try? await previews.image(for: window, maxPixels: maxPixels)) }
                    }
                }
            }
            // More than one batch can fit on a large display. Drain uncaptured visible cards even
            // in snapshot mode; failed captures wait for a new demand or the next live tick.
            if WindowThumbnailPlan.targets(filtered, selection: selection, visibleIDs: visibleThumbnailIDs, limit: .max)
                .contains(where: { !thumbnailAttemptedIDs.contains($0.id) }) {
                continuation.yield(())
            }
        }
    }

    /// Full-size image for the in-place preview of the selected window.
    func loadSelectedPreview(maxPixels: CGSize) async {
        guard permitsCapture(), let window = selected, window.windowID != nil, !window.minimized else {
            selectedPreview = nil
            return
        }
        let generation = thumbnailGeneration
        // Never keep another window's full-size image while the new capture is in flight.
        selectedPreview = nil
        if let thumbnail = thumbnails[window.id] { selectedPreview = (window.id, thumbnail) }
        let image = try? await previews.image(for: window, maxPixels: maxPixels)
        guard !Task.isCancelled, generation == thumbnailGeneration, selected?.id == window.id else { return }
        guard permitsCapture() else { selectedPreview = nil; return }
        guard let image else { return }
        selectedPreview = (window.id, NSImage(cgImage: image.cgImage, size: .zero))
    }

    /// Stops in-flight captures; cached images stay for the next session.
    func clearThumbnails() {
        thumbnailRequests?.finish()
        thumbnailRequests = nil
        thumbnailWorkerID = nil
        thumbnailGeneration = UUID()
        visibleThumbnailIDs = []
        thumbnailCapturedAt = [:]
        thumbnailAttemptedIDs = []
        unavailableThumbnails = []
        selectedPreview = nil
        if !permitsCapture() { thumbnails = [:]; thumbnailCosts = [:]; thumbnailAccessedAt = [:] }
    }

    func capturePreview() async {
        guard !previewBusy, let selected, selected.windowID != nil else { return }
        previewBusy = true; preview = nil; previewMessage = nil
        let id = selected.id
        let generation = thumbnailGeneration
        defer { previewBusy = false }
        do {
            let image = try await previews.image(for: selected, maxPixels: CGSize(width: 840, height: 520))
            guard !Task.isCancelled, generation == thumbnailGeneration, self.selected?.id == id else { return }
            guard permitsCapture() else { previewMessage = WindowPreviewError.permissionRequired.localizedDescription; return }
            preview = NSImage(cgImage: image.cgImage, size: .zero)
        } catch {
            guard !Task.isCancelled, generation == thumbnailGeneration, self.selected?.id == id else { return }
            previewMessage = error.localizedDescription
        }
    }

    func excludeSelected() {
        guard let path = selected?.applicationURL?.path else { return }
        let loaded = SwitcherExceptionStore.load(defaults)
        guard loaded.error == nil else { failure = loaded.error; return }
        var rules = loaded.rules
        if !rules.contains(where: { $0.enabled && $0.target == .applicationPath && $0.value == path && $0.visibility == .alwaysHide }) {
            rules.append(.init(target: .applicationPath, value: path, visibility: .alwaysHide))
        }
        guard SwitcherExceptionStore.save(rules, defaults) else {
            failure = String(localized: "İstisna kaydedilemedi. Kural sayısını ve uygulama hedefini kontrol et."); return
        }
        reloadExceptions()
        selection = nil
    }
}
