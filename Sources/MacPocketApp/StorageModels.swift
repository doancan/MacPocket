import AppKit
import MacPocketCore
import SwiftUI

/// Polls a scan control a few times per second, so progress never floods the main actor no matter
/// how fast the walkers run.
@MainActor
private func pollProgress(_ control: StorageScanControl, into update: @escaping @MainActor (StorageScanControl.Snapshot) -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        while !Task.isCancelled {
            update(control.snapshot)
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

// MARK: - Volume overview

@MainActor
final class StorageOverviewModel: ObservableObject {
    @Published private(set) var report: StorageOverviewReport?
    /// Live capacity, shown before the first category scan and refreshed after each one.
    @Published private(set) var volume: VolumeCapacity?
    @Published private(set) var scanning = false
    @Published private(set) var progress: StorageScanControl.Snapshot?
    @Published var failure: String?
    private var control: StorageScanControl?
    private var task: Task<Void, Never>?
    private var loaded = false
    private let cache = StorageOverviewCache.standard

    func loadIfNeeded() {
        // Free space is cheap to read and changes between visits; only the cached category scan is loaded once.
        if let current = try? VolumeCapacity.read() { volume = current }
        guard !loaded else { return }
        loaded = true
        let cache = cache
        Task { [weak self] in
            let cached = await Task.detached(priority: .utility) { cache.load() }.value
            guard let self, self.report == nil else { return }
            self.report = cached
        }
    }

    func scan() {
        guard !scanning else { return }
        let control = StorageScanControl(maximumDuration: 120, maximumEntries: 5_000_000)
        self.control = control
        scanning = true; failure = nil; progress = nil
        let cache = cache
        task = Task { [weak self] in
            let poller = pollProgress(control) { self?.progress = $0 }
            defer { poller.cancel() }
            do {
                let report = try await StorageOverviewScanner().scan(StorageOverviewOptions(), control: control)
                guard let self else { return }
                self.report = report
                self.volume = report.volume
                try? await Task.detached(priority: .utility) { try cache.save(report) }.value
            } catch is CancellationError {
                self?.failure = nil
            } catch {
                self?.failure = error.localizedDescription
            }
            self?.scanning = false
            self?.control = nil
        }
    }

    func cancel() {
        control?.cancel()
        task?.cancel()
    }
}

// MARK: - Space Lens

@MainActor
final class SpaceLensModel: ObservableObject {
    @Published private(set) var rootURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    @Published private(set) var tree: SpaceLensNode?
    @Published private(set) var scannedAt: Date?
    @Published private(set) var limitReached = false
    @Published private(set) var scanning = false
    /// Moving items to the Trash.
    @Published private(set) var working = false
    /// Path being expanded (a deeper folder loaded on demand); nil during a full scan.
    @Published private(set) var expandingPath: String?
    @Published private(set) var progress: StorageScanControl.Snapshot?
    @Published var currentPath: String? { didSet { if currentPath != oldValue { selection = [] } } }
    @Published var selection = Set<String>()
    @Published var failure: String?
    @Published var resultMessage: String?
    private var control: StorageScanControl?
    private var task: Task<Void, Never>?
    private let trashService = FileTrashService()

    var busy: Bool { scanning || working }

    var current: SpaceLensNode? {
        guard let tree else { return nil }
        return currentPath.flatMap { tree.node(at: $0) } ?? tree
    }

    /// Nodes from the scanned root down to the current folder.
    var breadcrumb: [SpaceLensNode] {
        guard let tree else { return [] }
        var trail = [tree]
        guard let target = currentPath, target != tree.path else { return trail }
        var node = tree
        while node.path != target, let next = node.children?.first(where: {
            $0.kind == .folder && (target == $0.path || target.hasPrefix($0.path + "/"))
        }) {
            trail.append(next)
            node = next
        }
        return trail
    }

    var selectedNodes: [SpaceLensNode] {
        guard let children = current?.children, !selection.isEmpty else { return [] }
        return children.filter { selection.contains($0.id) && $0.identity != nil }
    }

    var selectedBytes: Int64 { selectedNodes.reduce(0) { $0 + $1.allocatedBytes } }

    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Görselleştir")
        panel.message = String(localized: "Space Lens bu klasörü haritalar. Bağlantılar takip edilmez, diğer diskler atlanır.")
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }

    func scan(_ url: URL? = nil) {
        guard !busy else { return }
        if let url { rootURL = url }
        let root = rootURL
        let control = StorageScanControl(maximumDuration: 90, maximumEntries: 5_000_000)
        self.control = control
        scanning = true; expandingPath = nil; failure = nil; resultMessage = nil; progress = nil
        task = Task { [weak self] in
            let poller = pollProgress(control) { self?.progress = $0 }
            defer { poller.cancel() }
            do {
                let report = try await SpaceLensScanner().scan(root, control: control)
                guard let self else { return }
                tree = report.root
                rootURL = report.root.url
                scannedAt = report.scannedAt
                limitReached = report.limitReached
                currentPath = nil
                selection = []
            } catch is CancellationError {
            } catch {
                self?.failure = error.localizedDescription
            }
            self?.scanning = false
            self?.control = nil
        }
    }

    /// Opens a folder: drills down immediately when its children are loaded, otherwise scans it first.
    func open(_ node: SpaceLensNode) {
        guard node.kind == .folder, !busy else { return }
        guard node.needsExpansion else { currentPath = node.path; return }
        let control = StorageScanControl(maximumDuration: 60, maximumEntries: 3_000_000)
        self.control = control
        scanning = true; expandingPath = node.path; failure = nil; progress = nil
        task = Task { [weak self] in
            let poller = pollProgress(control) { self?.progress = $0 }
            defer { poller.cancel() }
            do {
                let report = try await SpaceLensScanner().scan(node.url, control: control)
                guard let self, let tree else { return }
                // A deeper scan of the same folder replaces the summary node; sizes above it are unchanged
                // because both scans measure the same subtree.
                self.tree = tree.replacing(node.path, with: report.root)
                if report.limitReached { limitReached = true }
                currentPath = node.path
            } catch is CancellationError {
            } catch {
                self?.failure = error.localizedDescription
            }
            self?.scanning = false
            self?.expandingPath = nil
            self?.control = nil
        }
    }

    func goTo(_ path: String) {
        guard !busy else { return }
        currentPath = path == tree?.path ? nil : path
    }

    func goUp() {
        let trail = breadcrumb
        guard trail.count > 1 else { return }
        goTo(trail[trail.count - 2].path)
    }

    func cancel() {
        control?.cancel()
        task?.cancel()
    }

    func toggle(_ node: SpaceLensNode) {
        guard node.identity != nil, node.kind != .remainder else { return }
        if selection.contains(node.id) { selection.remove(node.id) } else { selection.insert(node.id) }
    }

    func trashSelection() {
        guard !busy, let tree else { return }
        let root = tree.url
        let requests = selectedNodes.compactMap { node in
            node.identity.map { FileTrashRequest(url: node.url, identity: $0, root: root) }
        }
        guard !requests.isEmpty else { return }
        working = true; failure = nil; resultMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            let results = await trashService.trash(requests)
            let moved = Set(results.filter { $0.trashURL != nil }.map(\.id))
            let freed = selectedNodes.filter { moved.contains($0.path) }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            if !moved.isEmpty, let current = self.tree { self.tree = current.removing(moved) }
            selection = []
            let errors = results.compactMap(\.error)
            resultMessage = moved.isEmpty ? nil
                : String(localized: "\(moved.count) öğe Çöp’e taşındı (\(pocketDiskBytes(freed))). Finder’daki Çöp’ten geri alabilirsin; alan Çöp boşaltılınca açılır.")
            failure = errors.isEmpty ? nil : errors.prefix(3).joined(separator: "\n")
            working = false
        }
    }
}

// MARK: - Cleanup

struct CleanupSummary: Equatable {
    enum Kind { case movedToTrash, emptiedTrash }
    let kind: Kind
    let itemCount: Int
    let bytes: Int64
    /// Change of the volume's available capacity measured before and after the operation.
    let availableDelta: Int64?
    let failures: [String]
    let date: Date
}

@MainActor
@Observable
final class CleanupModel {
    private(set) var report: CleanupReport?
    private(set) var scanning = false
    private(set) var working = false
    private(set) var progress: StorageScanControl.Snapshot?
    var selection = Set<String>() { didSet { refreshSelection() } }
    var expanded = Set<CleanupTargetID>()
    var failure: String?
    private(set) var summary: CleanupSummary?
    var downloadsAgeDays = 90
    private(set) var protection = CleanupProtection.load(from: .standard)
    @ObservationIgnored private(set) var selectedBytes: Int64 = 0
    @ObservationIgnored private(set) var selectedItems: [CleanupItem] = []
    @ObservationIgnored private(set) var targets: [CleanupTarget] = CleanupCatalog.targets(home: URL(fileURLWithPath: NSHomeDirectory()))
    /// What the next scan covers; remembered between launches.
    var scanSelection: CleanupScanSelection {
        didSet { if scanSelection != oldValue { scanSelection.save(to: .standard) } }
    }
    /// Per-location sizes from earlier scans, shown on the category tiles.
    private(set) var lastSizes = CleanupLastScanSizes.load(from: .standard)
    @ObservationIgnored private var itemsByID: [String: CleanupItem] = [:]
    @ObservationIgnored private var control: StorageScanControl?
    @ObservationIgnored private var task: Task<Void, Never>?
    private let service = CleanupService()
    private let emptier = TrashEmptier()

    init() {
        scanSelection = CleanupScanSelection.load(from: .standard, targets: targets)
    }

    var scanProfile: CleanupProfile { scanSelection.profile(in: targets) }

    func applyProfile(_ profile: CleanupProfile) { scanSelection.apply(profile, targets: targets) }

    /// Back to choosing what to scan; the previous results are dropped.
    func editScanPlan() {
        guard !busy else { return }
        report = nil; summary = nil; failure = nil
        selection = []; itemsByID = [:]
    }

    /// No new entries for a few seconds: usually a macOS privacy prompt (Downloads, Mail) awaiting an answer.
    private(set) var stalled = false
    @ObservationIgnored private var lastVisited = -1
    @ObservationIgnored private var unchangedPolls = 0

    private func noteProgress(_ snapshot: StorageScanControl.Snapshot) {
        progress = snapshot
        if snapshot.visitedEntries == lastVisited { unchangedPolls += 1 } else { unchangedPolls = 0; lastVisited = snapshot.visitedEntries }
        let isStalled = unchangedPolls >= 16
        if isStalled != stalled { stalled = isStalled }
    }

    var busy: Bool { scanning || working }
    var trashReport: CleanupTargetReport? { report?.targets.first { $0.target.isTrash } }
    /// Selected items whose owning app is open right now.
    var selectedWarnings: Int { selectedItems.filter { $0.warning != nil }.count }

    func scan() {
        guard !busy else { return }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let catalog = CleanupCatalog.targets(home: home, downloadsAgeDays: downloadsAgeDays)
        self.targets = catalog
        let targets = catalog.filter { scanSelection.contains($0.id) }
        guard !targets.isEmpty else {
            failure = String(localized: "Taranacak konum seçilmedi. Temizlik sayfasından en az bir kategori seç.")
            return
        }
        let running = NSWorkspace.shared.runningApplications.map {
            RunningApplicationInfo(bundleID: $0.bundleIdentifier, name: $0.localizedName)
        }
        let control = StorageScanControl(maximumDuration: 90, maximumEntries: 4_000_000)
        self.control = control
        scanning = true; failure = nil; summary = nil; progress = nil
        stalled = false; lastVisited = -1; unchangedPolls = 0
        task = Task { [weak self] in
            let poller = pollProgress(control) { self?.noteProgress($0) }
            defer { poller.cancel() }
            do {
                let report = try await CleanupScanner().scan(targets, running: running, control: control)
                self?.apply(report)
            } catch is CancellationError {
            } catch {
                self?.failure = error.localizedDescription
            }
            self?.scanning = false
            self?.control = nil
        }
    }

    private func apply(_ report: CleanupReport) {
        self.report = report
        lastSizes.record(report)
        lastSizes.save(to: .standard)
        itemsByID = Dictionary(report.targets.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        selection = Set(report.targets.filter { isSelectable($0.target) }.flatMap(\.items)
            .filter { $0.preselected && !protection.contains($0.id) }.map(\.id))
    }

    /// Trash and separately managed data are listed but never part of a cleanup selection.
    private func isSelectable(_ target: CleanupTarget) -> Bool { !target.isTrash && !target.isManagedSeparately }

    private func refreshSelection() {
        selectedItems = selection.compactMap { itemsByID[$0] }.filter { item in
            guard let target = targets.first(where: { $0.id == item.targetID }) else { return false }
            return isSelectable(target) && !protection.contains(item.id)
        }
        selectedBytes = selectedItems.reduce(0) { $0 + $1.bytes }
    }

    func cancel() {
        control?.cancel()
        task?.cancel()
    }

    // MARK: Selection helpers

    enum TargetSelection { case none, some, all }

    func selectionState(of target: CleanupTargetReport) -> TargetSelection {
        let selected = target.items.filter { selection.contains($0.id) }.count
        if selected == 0 { return .none }
        return selected == target.items.count ? .all : .some
    }

    func selectedBytes(in target: CleanupTargetReport) -> Int64 {
        target.items.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    func setTarget(_ target: CleanupTargetReport, selected: Bool) {
        guard isSelectable(target.target) else { return }
        let ids = Set(target.items.map(\.id).filter { !protection.contains($0) })
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func toggle(_ item: CleanupItem) {
        guard let target = targets.first(where: { $0.id == item.targetID }), isSelectable(target), !protection.contains(item.id) else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    /// "Keep": a protected item leaves the selection and is skipped by every later scan and cleanup.
    func toggleProtection(_ item: CleanupItem) {
        protection.toggle(item.id)
        protection.save(to: .standard)
        selection.remove(item.id)
    }

    func toggleExpanded(_ id: CleanupTargetID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: Actions

    /// Moves the selected items to the Trash; every item is revalidated right before it moves.
    func clean() {
        guard !busy else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
        let targets = targets
        working = true; failure = nil; summary = nil
        PocketOperationState.shared.preventTermination = true
        task = Task { [weak self] in
            guard let self else { return }
            let before = try? VolumeCapacity.read()
            let results = await service.moveToTrash(items, targets: targets, protectedPaths: protection.paths)
            let after = try? VolumeCapacity.read()
            let moved = Set(results.filter { $0.trashURL != nil }.map(\.id))
            let bytes = items.filter { moved.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
            removeItems(moved)
            summary = CleanupSummary(kind: .movedToTrash, itemCount: moved.count, bytes: bytes,
                                     availableDelta: delta(before, after), failures: failureLines(results), date: Date())
            working = false
            PocketOperationState.shared.preventTermination = false
        }
    }

    /// Permanently deletes the listed Trash items. Not recoverable; the view asks for explicit consent first.
    func emptyTrash() {
        guard !busy, let trash = trashReport, !trash.items.isEmpty else { return }
        let items = trash.items
        let emptier = emptier
        working = true; failure = nil; summary = nil
        PocketOperationState.shared.preventTermination = true
        task = Task { [weak self] in
            let before = try? VolumeCapacity.read()
            let result = await emptier.empty(items)
            let after = try? VolumeCapacity.read()
            guard let self else { return }
            removeItems(Set(result.removed.map(\.path)))
            summary = CleanupSummary(kind: .emptiedTrash, itemCount: result.removed.count, bytes: result.removedBytes,
                                     availableDelta: delta(before, after),
                                     failures: result.failures.prefix(5).map { "\($0.url.lastPathComponent): \($0.message)" },
                                     date: Date())
            working = false
            PocketOperationState.shared.preventTermination = false
        }
    }

    func dismissSummary() { summary = nil }

    private func delta(_ before: VolumeCapacity?, _ after: VolumeCapacity?) -> Int64? {
        guard let before, let after else { return nil }
        return after.availableBytes - before.availableBytes
    }

    private func failureLines(_ results: [FileTrashResult]) -> [String] {
        results.compactMap { result in result.error.map { "\(result.source.lastPathComponent): \($0)" } }.prefix(5).map { $0 }
    }

    private func removeItems(_ ids: Set<String>) {
        guard !ids.isEmpty, var report else { return }
        for index in report.targets.indices {
            report.targets[index].items.removeAll { ids.contains($0.id) }
        }
        self.report = report
        ids.forEach { itemsByID.removeValue(forKey: $0) }
        selection.subtract(ids)
    }
}
