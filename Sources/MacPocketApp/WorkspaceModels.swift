import AppKit
import Combine
import MacPocketCore
import SwiftUI

/// Sections of the Disk Analizi page.
enum StorageTab: String, CaseIterable, Identifiable {
    case overview = "Genel Bakış", lens = "Space Lens", files = "Dosya Araçları"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .lens: "square.grid.3x3.square"
        case .files: "doc.text.magnifyingglass"
        }
    }
    var localizedTitle: String {
        switch self {
        case .overview: String(localized: "Genel Bakış")
        case .lens: "Space Lens"
        case .files: String(localized: "Dosya Araçları")
        }
    }
}

enum FileWorkspaceScope: String, CaseIterable, Identifiable {
    case large = "Dosyalar", folders = "Klasörler", old = "Eski Dosyalar", duplicates = "Yinelenenler"
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .large: String(localized: "Dosyalar")
        case .folders: String(localized: "Klasörler")
        case .old: String(localized: "Eski Dosyalar")
        case .duplicates: String(localized: "Yinelenenler")
        }
    }
}

/// App-side copy of a duplicate group so moved files can be dropped without rescanning.
struct FileDuplicateGroup: Identifiable {
    let id: String
    let files: [ScannedFile]
    var duplicateBytes: Int64 { (files.first?.bytes ?? 0) * Int64(max(0, files.count - 1)) }
}

struct FileResultRow: Identifiable {
    let url: URL
    let identity: FileIdentity
    let bytes: Int64
    var group = ""
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var parent: String { group.isEmpty ? url.deletingLastPathComponent().path : group }
    var modified: Date { Date(timeIntervalSince1970: Double(identity.modifiedSeconds)) }
}

@MainActor
final class FileWorkspaceModel: ObservableObject {
    @Published var root: URL?
    @Published private(set) var report: FileScanReport? { didSet { rebuildBaseRows() } }
    @Published private(set) var duplicates: [FileDuplicateGroup] = [] { didSet { rebuildBaseRows() } }
    @Published var scope = FileWorkspaceScope.large {
        didSet {
            // Shortcuts elsewhere set a scope to open a file tool; always reveal the tools tab.
            if storageTab != .files { storageTab = .files }
            guard scope != oldValue else { return }
            selection = []; rebuildBaseRows()
        }
    }
    @Published var storageTab = StorageTab.overview
    /// Volume categories, Space Lens and System Junk; idle until their page is opened.
    let overview = StorageOverviewModel()
    let lens = SpaceLensModel()
    let junk = CleanupModel()
    @Published var selection = Set<String>() { didSet { refreshSelection() } }
    @Published var search = "" { didSet { if search != oldValue { applyFilters() } } }
    @Published var busy = false
    @Published var progress = ""
    @Published var failure: String?
    @Published var resultMessage: String?
    @Published var minimumMB = 0.0 { didSet { if minimumMB != oldValue { applyFilters() } } }
    @Published var olderDays = 90.0 { didSet { if olderDays != oldValue, scope == .old { rebuildBaseRows() } } }

    /// Filtered and sorted rows for the current scope. Cached: recomputed only when an input changes.
    @Published private(set) var rows: [FileResultRow] = []
    /// Selected rows that are currently visible; trash and Finder actions only act on these.
    private(set) var selectedRows: [FileResultRow] = []
    private(set) var selectedBytes: Int64 = 0
    /// False when every copy of some duplicate group is selected.
    private(set) var preservesDuplicateOriginals = true
    /// Paths moved to Trash since the last scan. Hidden from results (with their descendants) until a rescan.
    private var trashedPaths = Set<String>()
    /// Scope + trash filtered rows, already sorted; search and size filters run on top of this.
    private var baseRows: [FileResultRow] = []

    private var operation: Task<Void, Never>?
    private let scanner = FileScanner()
    private let finder = DuplicateFinder()
    private let trashService = FileTrashService()
    private let cleanup: Bool

    init(cleanup: Bool = false) {
        self.cleanup = cleanup
        if cleanup { root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"); scope = .folders }
        storageTab = .overview
    }

    /// True when the visible results changed since the last scan (items were moved to Trash).
    var hasTrashedItems: Bool { !trashedPaths.isEmpty }

    // MARK: Derived rows

    private func rebuildBaseRows() {
        guard let report else {
            baseRows = []
            applyFilters()
            return
        }
        let values: [FileResultRow]
        switch scope {
        case .folders:
            let rootPath = report.root.path
            values = report.folders.map { FileResultRow(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
                + report.files.lazy.filter { $0.url.deletingLastPathComponent().path == rootPath }
                    .map { FileResultRow(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
        case .duplicates:
            values = duplicates.enumerated().flatMap { index, group in
                group.files.map { FileResultRow(url: $0.url, identity: $0.identity, bytes: $0.bytes,
                                                group: String(localized: "Grup \(index + 1) · \(group.files.count) aynı içerik")) }
            }
        case .old:
            let cutoff = Date().addingTimeInterval(-olderDays * 86_400)
            values = report.files.lazy.filter { $0.modifiedAt < cutoff }
                .map { FileResultRow(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
        case .large:
            values = report.files.map { FileResultRow(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
        }
        let visible = trashedPaths.isEmpty ? values : values.filter { !isTrashed($0.url, rootPath: report.root.path) }
        // Duplicate groups keep their own order so copies stay adjacent; other scopes sort by size.
        baseRows = scope == .duplicates ? visible
            : visible.sorted { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
        applyFilters()
    }

    private func applyFilters() {
        let minimumBytes = Int64(minimumMB * 1_048_576)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if minimumBytes == 0, query.isEmpty {
            rows = baseRows
        } else {
            rows = baseRows.filter { row in
                row.bytes >= minimumBytes && (query.isEmpty || row.url.path.localizedCaseInsensitiveContains(query))
            }
        }
        // Drop selections that are no longer visible so actions never touch hidden rows.
        let visibleIDs = Set(rows.lazy.map(\.id))
        let kept = selection.intersection(visibleIDs)
        if kept != selection { selection = kept } else { refreshSelection() }
    }

    private func refreshSelection() {
        selectedRows = selection.isEmpty ? [] : rows.filter { selection.contains($0.id) }
        selectedBytes = selectedRows.reduce(0) { $0 + $1.bytes }
        preservesDuplicateOriginals = scope != .duplicates
            || !duplicates.contains { group in group.files.allSatisfy { selection.contains($0.id) } }
    }

    /// A path is hidden when it or one of its ancestors (below the scan root) was moved to Trash.
    private func isTrashed(_ url: URL, rootPath: String) -> Bool {
        var path = url.path
        while path.count > rootPath.count {
            if trashedPaths.contains(path) { return true }
            let parent = (path as NSString).deletingLastPathComponent
            guard parent != path else { break }
            path = parent
        }
        return false
    }

    // MARK: Actions

    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Klasörü Seç"); panel.message = String(localized: "Yalnız seçtiğin klasör taranır. Bağlantılar takip edilmez.")
        if let root { panel.directoryURL = root }
        if panel.runModal() == .OK, let url = panel.url { root = url; scan() }
    }

    func useRoot(_ root: URL, scope: FileWorkspaceScope = .large) {
        guard !busy else { return }
        self.root = root
        trashedPaths = []
        report = nil; duplicates = []; selection = []; resultMessage = nil; failure = nil
        self.scope = scope
    }

    func scan() {
        guard let root, !busy else { return }
        busy = true; failure = nil; resultMessage = nil; selection = []
        trashedPaths = []
        report = nil; duplicates = []
        progress = String(localized: "Klasör inceleniyor…")
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            do {
                report = try await scanner.scan(root) { [weak self] value in
                    await MainActor.run { self?.progress = String(localized: "\(value.fileCount) dosya · \(pocketDiskBytes(value.bytes))") }
                }
                if scope == .duplicates { try await compareDuplicates() }
            } catch is CancellationError { progress = String(localized: "Tarama iptal edildi.") }
            catch { failure = error.localizedDescription }
        }
    }

    func findDuplicates() {
        guard report != nil, !busy else { return }
        busy = true; failure = nil; selection = []
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            do { try await compareDuplicates() }
            catch is CancellationError { progress = String(localized: "Karşılaştırma iptal edildi.") }
            catch { failure = error.localizedDescription }
        }
    }

    private func compareDuplicates() async throws {
        guard let report else { return }
        progress = String(localized: "Aynı boyuttaki dosyalar içerikleriyle karşılaştırılıyor…")
        let files = trashedPaths.isEmpty ? report.files : report.files.filter { !isTrashed($0.url, rootPath: report.root.path) }
        let groups = try await finder.groups(in: files) { [weak self] completed, count in
            await MainActor.run { self?.progress = String(localized: "\(completed) / \(count) dosya karşılaştırıldı") }
        }
        duplicates = groups.map { FileDuplicateGroup(id: $0.id, files: $0.files) }
            .sorted { $0.duplicateBytes == $1.duplicateBytes ? $0.id < $1.id : $0.duplicateBytes > $1.duplicateBytes }
        scope = .duplicates
        progress = String(localized: "\(duplicates.count) yinelenen grup bulundu.")
    }

    func selectExtraCopies() {
        selection = Set(duplicates.flatMap { $0.files.dropFirst().map(\.id) })
    }

    func cancel() { operation?.cancel() }

    func trashSelection() {
        guard !busy, preservesDuplicateOriginals, let root = report?.root else { return }
        let requests = selectedRows.map { FileTrashRequest(url: $0.url, identity: $0.identity, root: root) }
        guard !requests.isEmpty else { return }
        busy = true; failure = nil; resultMessage = nil
        progress = String(localized: "\(requests.count) öğe Çöp’e taşınıyor…")
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            let results = await trashService.trash(requests)
            let moved = Set(results.filter { $0.trashURL != nil }.map(\.id))
            let errors = results.compactMap(\.error)
            if !moved.isEmpty {
                trashedPaths.formUnion(moved)
                // Keep the report; hide moved items and drop duplicate groups that no longer have copies.
                let rootPath = root.path
                duplicates = duplicates.compactMap { group in
                    let remaining = group.files.filter { !isTrashed($0.url, rootPath: rootPath) }
                    return remaining.count >= 2 ? FileDuplicateGroup(id: group.id, files: remaining) : nil
                }  // Setting `duplicates` rebuilds the cached rows with the new trashed set.
            }
            selection = []
            resultMessage = moved.isEmpty ? nil
                : String(localized: "\(moved.count) öğe Çöp’e taşındı. Toplamlar bir sonraki taramada güncellenir.")
            failure = errors.isEmpty ? nil : errors.prefix(3).joined(separator: "\n")
        }
    }
}

@MainActor
@Observable

final class ApplicationWorkspaceModel {
    var applications: [InstalledApplication] = []
    var casks: [HomebrewCask] = []
    var updates: [HomebrewCask] = []
    var updateSettings = ApplicationUpdateSettings.load(from: .standard) {
        didSet {
            guard updateSettings != oldValue else { return }
            updateSettings.save(to: .standard)
            updatesCheckedAt = nil; updateSourceResults = [:]; remoteUpdates = []; updates = []; updateCheckCancelled = false
        }
    }
    private(set) var remoteUpdates: [ApplicationUpdateFinding] = []
    private(set) var updateSourceResults: [ApplicationUpdateSource: ApplicationUpdateSourceResult] = [:]
    private(set) var currentUpdateSource: ApplicationUpdateSource?
    private(set) var updateProgress: String?
    private(set) var updateCheckCancelled = false
    var loaded = false
    var busy = false
    var checkingUpdates = false
    var updatingToken: String?
    var packageAction = String(localized: "güncelleniyor")
    var updatesCheckedAt: Date?
    var failure: String?
    var resultMessage: String?
    var showUpdates = false
    var selection: String?
    var search = ""
    @ObservationIgnored private var additionalRoots: [URL] = []
    private let inventory = ApplicationInventory()
    private let homebrew = HomebrewApplications()
    private let updateScanner: ApplicationUpdateScanner
    private let uninstallProcesses: any UninstallProcessManaging
    private let uninstallTrash: @Sendable ([FileTrashRequest]) async -> [FileTrashResult]
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    init(updateScanner: ApplicationUpdateScanner = ApplicationUpdateScanner(),
         uninstallProcesses: any UninstallProcessManaging = ApplicationUninstallProcesses(),
         uninstallTrash: @escaping @Sendable ([FileTrashRequest]) async -> [FileTrashResult] = { await FileTrashService().trash($0) }) {
        self.updateScanner = updateScanner; self.uninstallProcesses = uninstallProcesses; self.uninstallTrash = uninstallTrash
    }
    func uninstallPreparation(for application: InstalledApplication) -> UninstallPreparationModel {
        .init(application: application, service: uninstallProcesses)
    }

    var visibleRemoteUpdates: [ApplicationUpdateFinding] { remoteUpdates.filter { updateSettings.sources.contains($0.source) } }
    var visibleHomebrewUpdates: [HomebrewCask] { updateSettings.sources.contains(.homebrew) ? updates : [] }
    var availableUpdateCount: Int { visibleHomebrewUpdates.count + visibleRemoteUpdates.count }

    var selectedApplication: InstalledApplication? { applications.first { $0.id == selection } }
    var filtered: [InstalledApplication] {
        applications.filter { search.isEmpty || "\($0.name) \($0.bundleID)".localizedCaseInsensitiveContains(search) }
    }
    func load() async {
        guard !busy, !checkingUpdates else { return }
        busy = true
        defer { busy = false }
        do { applications = try await inventory.scan(roots: ApplicationInventory.defaultRoots + additionalRoots); loaded = true; failure = nil }
        catch { failure = error.localizedDescription }
        if casks.isEmpty { casks = (try? await homebrew.installed()) ?? [] }
    }
    func chooseApplicationFolder() {
        guard !busy, !checkingUpdates, updatingToken == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = String(localized: "Envantere Ekle")
        panel.message = String(localized: "Standart Applications konumlarına ek olarak bu klasördeki uygulamalar incelenir.")
        if panel.runModal() == .OK, let root = panel.url {
            if !additionalRoots.contains(root) { additionalRoots.append(root) }
            Task { await load() }
        }
    }
    func checkUpdates() async {
        guard !busy, !checkingUpdates, updatingToken == nil, !updateSettings.sources.isEmpty else { return }
        checkingUpdates = true; failure = nil; updateCheckCancelled = false; updateSourceResults = [:]; remoteUpdates = []; updates = []
        let settings = updateSettings
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.checkingUpdates = false; self.currentUpdateSource = nil; self.updateProgress = nil; self.updateTask = nil }
            if !self.loaded {
                do {
                    self.applications = try await self.inventory.scan(roots: ApplicationInventory.defaultRoots + self.additionalRoots)
                    self.loaded = true
                    self.casks = (try? await self.homebrew.installed()) ?? []
                } catch {
                    if Task.isCancelled { self.updateCheckCancelled = true } else { self.failure = error.localizedDescription }
                    return
                }
            }
            let candidates = self.applications.filter { self.cask(for: $0) == nil }
            for source in ApplicationUpdateSource.allCases where settings.sources.contains(source) {
                if Task.isCancelled { self.updateCheckCancelled = true; break }
                self.currentUpdateSource = source; self.updateProgress = source.localizedTitle
                do {
                    let result: ApplicationUpdateSourceResult
                    if source == .homebrew {
                        let updates = try await self.homebrew.updates()
                        try Task.checkCancellation(); self.updates = updates
                        result = .init(checked: self.casks.count)
                    } else {
                        result = try await self.updateScanner.check(source, applications: candidates, settings: settings) { [weak self] done, total in
                            await MainActor.run { self?.updateProgress = String(localized: "\(source.localizedTitle) · \(done)/\(total) uygulama") }
                        }
                    }
                    try Task.checkCancellation()
                    self.updateSourceResults[source] = result
                    self.remoteUpdates += result.findings
                } catch {
                    if Task.isCancelled { self.updateCheckCancelled = true; break }
                    self.updateSourceResults[source] = .init(failures: [error.localizedDescription])
                }
            }
            self.updatesCheckedAt = Date()
        }
        updateTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    func cancelUpdateCheck() { updateTask?.cancel() }
    func cask(for app: InstalledApplication) -> HomebrewCask? {
        let parent = app.url.deletingLastPathComponent().standardizedFileURL
        guard parent.path == "/Applications" || parent.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path else { return nil }
        return casks.first { cask in cask.applicationNames.contains { URL(fileURLWithPath: $0).lastPathComponent == app.url.lastPathComponent } }
    }
    /// Installed application bundle that a Homebrew cask manages, used for icons in the updates list.
    func application(for cask: HomebrewCask) -> InstalledApplication? {
        let installed = casks.first { $0.token == cask.token }
        let names = Set((cask.applicationNames + (installed?.applicationNames ?? [])).map { URL(fileURLWithPath: $0).lastPathComponent })
        guard !names.isEmpty else { return nil }
        return applications.first { names.contains($0.url.lastPathComponent) && self.cask(for: $0)?.token == cask.token }
            ?? applications.first { names.contains($0.url.lastPathComponent) }
    }
    @discardableResult
    func uninstall(_ plan: UninstallPlan, selected: Set<String>) async -> Bool {
        guard !busy, !checkingUpdates, updatingToken == nil else { return false }
        guard !selected.isEmpty, selected.isSubset(of: Set(plan.candidates.map(\.id))) else {
            failure = String(localized: "Kaldırılacak öğeleri geçerli plandan seç."); return false
        }
        busy = true
        failure = nil; resultMessage = nil
        defer { busy = false; updatingToken = nil; PocketOperationState.shared.preventTermination = false }
        var results: [FileTrashResult] = [], packageResult = "", operationFailure: String?
        do {
            try await requireStopped(plan.application, validateBundle: true)
            // Graceful quit can save preferences. Refresh identities, retain only explicitly selected paths,
            // and never select newly discovered files or user-data categories automatically.
            let fresh = try UninstallPlanner.plan(plan.application, home: plan.home)
            var requests = fresh.candidates.filter { selected.contains($0.id) }.map(\.request)
            requests.sort { !$0.applicationBundle && $1.applicationBundle }
            var removedByHomebrew = false
            if let cask = cask(for: plan.application), selected.contains(plan.application.id) {
                try await requireStopped(plan.application, validateBundle: true)
                updatingToken = cask.token; packageAction = String(localized: "kaldırılıyor")
                PocketOperationState.shared.preventTermination = true
                packageResult = try await homebrew.uninstall(cask.token); removedByHomebrew = true
                requests.removeAll { $0.applicationBundle }
                casks = (try? await homebrew.installed()) ?? []
            }
            for request in requests {
                try Task.checkCancellation()
                try await requireStopped(plan.application, validateBundle: !removedByHomebrew)
                let moved = await uninstallTrash([request]); results += moved
                if moved.count != 1 || moved.contains(where: { $0.trashURL == nil }) {
                    operationFailure = moved.compactMap(\.error).first ?? String(localized: "Seçilen öğe taşınamadı; kalan öğelere dokunulmadı."); break
                }
            }
        } catch is CancellationError { operationFailure = String(localized: "Kaldırma durduruldu; kalan öğelere dokunulmadı.") }
        catch { operationFailure = error.localizedDescription }
        if !results.isEmpty || !packageResult.isEmpty {
            resultMessage = String(localized: "\(results.filter { $0.trashURL != nil }.count) öğe Çöp’e taşındı.") + (packageResult.isEmpty ? "" : "\nHomebrew: \(packageResult)")
        }
        if !FileManager.default.fileExists(atPath: plan.application.url.path) {
            applications.removeAll { $0.id == plan.application.id }
        }
        failure = operationFailure
        if operationFailure == nil, resultMessage == nil { resultMessage = String(localized: "Seçili öğeler artık bu konumda yok.") }
        if operationFailure == nil { selection = nil }
        return operationFailure == nil
    }
    private func requireStopped(_ application: InstalledApplication, validateBundle: Bool) async throws {
        let running = try await uninstallProcesses.inspect(application, validateBundle: validateBundle)
        guard running.isEmpty else {
            throw NSError(domain: "MacPocket.Uninstall", code: 3, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "\(application.name) veya yardımcı süreçleri çalışıyor. Dosyalar kaldırılmadan önce kapatılmaları gerekiyor.")])
        }
        try Task.checkCancellation()
    }
    func upgrade(_ cask: HomebrewCask) async {
        guard !busy, !checkingUpdates, updatingToken == nil, !cask.pinned else { return }
        updatingToken = cask.token; packageAction = String(localized: "güncelleniyor"); failure = nil
        PocketOperationState.shared.preventTermination = true
        defer { updatingToken = nil; PocketOperationState.shared.preventTermination = false }
        do {
            resultMessage = try await homebrew.upgrade(cask.token)
            updates = try await homebrew.updates(); updatesCheckedAt = Date()
            await load()
        } catch { failure = error.localizedDescription }
    }
}
