import AppKit
import MacPocketCore
import SwiftUI

enum FileWorkspaceScope: String, CaseIterable, Identifiable {
    case large = "Dosyalar", folders = "Klasörler", old = "Eski Dosyalar", duplicates = "Yinelenenler"
    var id: String { rawValue }
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
    @Published var report: FileScanReport?
    @Published var duplicates: [DuplicateFileGroup] = []
    @Published var scope = FileWorkspaceScope.large
    @Published var selection = Set<String>()
    @Published var search = ""
    @Published var busy = false
    @Published var progress = ""
    @Published var failure: String?
    @Published var resultMessage: String?
    @Published var minimumMB = 0.0
    @Published var olderDays = 90.0
    private var operation: Task<Void, Never>?
    private let scanner = FileScanner()
    private let finder = DuplicateFinder()
    private let trashService = FileTrashService()
    private let cleanup: Bool

    init(cleanup: Bool = false) {
        self.cleanup = cleanup
        if cleanup { root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"); scope = .folders }
    }

    var rows: [FileResultRow] {
        guard let report else { return [] }
        let values: [FileResultRow]
        switch scope {
        case .folders:
            values = report.folders.map { .init(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
                + report.files.filter { $0.url.deletingLastPathComponent().path == report.root.path }
                    .map { .init(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
        case .duplicates:
            values = duplicates.enumerated().flatMap { index, group in
                group.files.map { FileResultRow(url: $0.url, identity: $0.identity, bytes: $0.bytes, group: "Grup \(index + 1) · \(group.files.count) aynı içerik") }
            }
        default:
            values = report.files.filter { file in
                scope != .old || file.modifiedAt < Date().addingTimeInterval(-olderDays * 86400)
            }.map { .init(url: $0.url, identity: $0.identity, bytes: $0.bytes) }
        }
        return values.filter { row in
            row.bytes >= Int64(minimumMB * 1_048_576)
                && (search.isEmpty || row.url.path.localizedCaseInsensitiveContains(search))
        }.sorted { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
    }
    var selectedRows: [FileResultRow] { rows.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedRows.reduce(0) { $0 + $1.bytes } }
    var preservesDuplicateOriginals: Bool {
        scope != .duplicates || !duplicates.contains { group in group.files.allSatisfy { selection.contains($0.id) } }
    }

    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Klasörü Seç"; panel.message = "Yalnız seçtiğin klasör taranır. Bağlantılar takip edilmez."
        if let root { panel.directoryURL = root }
        if panel.runModal() == .OK, let url = panel.url { root = url; scan() }
    }

    func useRoot(_ root: URL, scope: FileWorkspaceScope = .large) {
        guard !busy else { return }
        self.root = root
        self.scope = scope
        report = nil; duplicates = []; selection = []; resultMessage = nil
    }

    func scan() {
        guard let root, !busy else { return }
        busy = true; report = nil; failure = nil; resultMessage = nil; selection = []; duplicates = []
        progress = "Klasör inceleniyor…"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            do {
                report = try await scanner.scan(root) { [weak self] value in
                    await MainActor.run { self?.progress = "\(value.fileCount.formatted()) dosya · \(pocketBytes(UInt64(max(0, value.bytes))))" }
                }
                if scope == .duplicates { try await compareDuplicates() }
            } catch is CancellationError { progress = "Tarama iptal edildi." }
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
            catch is CancellationError { progress = "Karşılaştırma iptal edildi." }
            catch { failure = error.localizedDescription }
        }
    }
    private func compareDuplicates() async throws {
        guard let report else { return }
        progress = "Aynı boyuttaki dosyalar içerikleriyle karşılaştırılıyor…"
        duplicates = try await finder.groups(in: report.files) { [weak self] completed, count in
            await MainActor.run { self?.progress = "\(completed.formatted()) / \(count.formatted()) dosya karşılaştırıldı" }
        }
        scope = .duplicates
        progress = "\(duplicates.count.formatted()) yinelenen grup bulundu."
    }
    func selectExtraCopies() {
        selection = Set(duplicates.flatMap { $0.files.dropFirst().map(\.id) })
    }
    func cancel() { operation?.cancel() }

    func trashSelection() {
        guard !busy, preservesDuplicateOriginals, let root = report?.root else { return }
        let requests = selectedRows.map { FileTrashRequest(url: $0.url, identity: $0.identity, root: root) }
        guard !requests.isEmpty else { return }
        busy = true
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            let results = await trashService.trash(requests)
            let moved = results.filter { $0.trashURL != nil }.count
            let errors = results.compactMap(\.error)
            resultMessage = "\(moved) öğe Çöp’e taşındı. Güncel sonuç için yeniden tara."
            failure = errors.isEmpty ? nil : errors.prefix(3).joined(separator: "\n")
            report = nil; duplicates = []; selection = []
        }
    }
}

@MainActor
final class ApplicationWorkspaceModel: ObservableObject {
    @Published var applications: [InstalledApplication] = []
    @Published var casks: [HomebrewCask] = []
    @Published var updates: [HomebrewCask] = []
    @Published var loaded = false
    @Published var busy = false
    @Published var checkingUpdates = false
    @Published var updatingToken: String?
    @Published var packageAction = "güncelleniyor"
    @Published var updatesCheckedAt: Date?
    @Published var failure: String?
    @Published var resultMessage: String?
    @Published var showUpdates = false
    @Published var selection: String?
    @Published var search = ""
    private var additionalRoots: [URL] = []
    private let inventory = ApplicationInventory()
    private let homebrew = HomebrewApplications()
    private let trashService = FileTrashService()

    var selectedApplication: InstalledApplication? { applications.first { $0.id == selection } }
    var filtered: [InstalledApplication] {
        applications.filter { search.isEmpty || "\($0.name) \($0.bundleID)".localizedCaseInsensitiveContains(search) }
    }
    func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { applications = try await inventory.scan(roots: ApplicationInventory.defaultRoots + additionalRoots); loaded = true; failure = nil }
        catch { failure = error.localizedDescription }
        if casks.isEmpty { casks = (try? await homebrew.installed()) ?? [] }
    }
    func chooseApplicationFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Envantere Ekle"
        panel.message = "Standart Applications konumlarına ek olarak bu klasördeki uygulamalar incelenir."
        if panel.runModal() == .OK, let root = panel.url {
            if !additionalRoots.contains(root) { additionalRoots.append(root) }
            Task { await load() }
        }
    }
    func checkUpdates() async {
        guard !busy, !checkingUpdates, updatingToken == nil else { return }
        checkingUpdates = true; failure = nil
        defer { checkingUpdates = false }
        do { updates = try await homebrew.updates(); updatesCheckedAt = Date() }
        catch { failure = error.localizedDescription }
    }
    func cask(for app: InstalledApplication) -> HomebrewCask? {
        let parent = app.url.deletingLastPathComponent().standardizedFileURL
        guard parent.path == "/Applications" || parent.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path else { return nil }
        return casks.first { cask in cask.applicationNames.contains { URL(fileURLWithPath: $0).lastPathComponent == app.url.lastPathComponent } }
    }
    func uninstall(_ plan: UninstallPlan, selected: Set<String>) async {
        guard !busy, !checkingUpdates, updatingToken == nil else { return }
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == plan.application.bundleID }) else {
            failure = "Kaldırmadan önce \(plan.application.name) uygulamasını kapatmalısın."; return
        }
        busy = true
        failure = nil
        defer { busy = false; updatingToken = nil; PocketOperationState.shared.preventTermination = false }
        var requests = plan.candidates.filter { selected.contains($0.id) }.map(\.request)
        var packageResult = ""
        if let cask = cask(for: plan.application), selected.contains(plan.application.id) {
            updatingToken = cask.token; packageAction = "kaldırılıyor"
            PocketOperationState.shared.preventTermination = true
            do {
                try plan.candidates[0].request.validate()
                packageResult = try await homebrew.uninstall(cask.token)
                requests.removeAll { $0.url == plan.application.url }
                casks = (try? await homebrew.installed()) ?? []
            } catch { failure = error.localizedDescription; return }
        }
        let results = await trashService.trash(requests)
        let errors = results.compactMap(\.error)
        resultMessage = "\(results.filter { $0.trashURL != nil }.count) öğe Çöp’e taşındı." + (packageResult.isEmpty ? "" : "\nHomebrew: \(packageResult)")
        failure = errors.isEmpty ? nil : errors.prefix(3).joined(separator: "\n")
        busy = false
        await load()
        if !errors.isEmpty { failure = errors.prefix(3).joined(separator: "\n") }
        selection = nil
    }
    func upgrade(_ cask: HomebrewCask) async {
        guard !busy, !checkingUpdates, updatingToken == nil, !cask.pinned else { return }
        updatingToken = cask.token; packageAction = "güncelleniyor"; failure = nil
        PocketOperationState.shared.preventTermination = true
        defer { updatingToken = nil; PocketOperationState.shared.preventTermination = false }
        do {
            resultMessage = try await homebrew.upgrade(cask.token)
            updates = try await homebrew.updates(); updatesCheckedAt = Date()
            await load()
        } catch { failure = error.localizedDescription }
    }
}
