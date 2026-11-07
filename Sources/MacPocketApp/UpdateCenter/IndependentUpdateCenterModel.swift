import AppKit
import Combine
import MacPocketCore
import Sparkle

struct IndependentUpdateFinding: Identifiable {
    var id: String { app.id }
    let app: InstalledApplication
    let installed: String
    let available: String
    let source: String
    let releaseURL: URL?
}
@MainActor final class IndependentUpdateCenterModel: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var findings: [IndependentUpdateFinding] = []
    @Published private(set) var checking = false
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var checked = 0
    @Published private(set) var failures: [String] = []
    @Published private(set) var checkedAt: Date?
    @Published private(set) var cancelled = false
    @Published var includeAppStore = false
    @Published var includePrereleases = false
    @Published private(set) var repositories: [String: String]
    private let defaults: UserDefaults
    private let scanner = ApplicationUpdateScanner()
    private let comparator = SUStandardVersionComparator()
    private var task: Task<Void, Never>?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        repositories = defaults.dictionary(forKey: "MacPocket.updateCenter.repositories") as? [String:String] ?? [:]
    }
    func load() async {
        guard !loading, !checking else { return }
        loading = true; defer { loading = false; loaded = true }
        let inventory = ApplicationWorkspaceModel()
        await inventory.load()
        applications = inventory.applications.filter {
            $0.channel != .system && $0.channel != .setapp &&
            $0.bundleID != "com.doancan.MacPocket" && inventory.cask(for: $0) == nil
        }
        if let error = inventory.failure { failures = [error] }
    }
    func saveRepository(for bundleID: String, value: String?) -> Bool {
        if let value {
            guard let repository = GitHubRepository(value) else { return false }
            repositories[bundleID] = repository.slug
        } else { repositories.removeValue(forKey: bundleID) }
        defaults.set(repositories, forKey: "MacPocket.updateCenter.repositories")
        findings = []; checkedAt = nil
        return true
    }
    func check() async {
        guard !checking, loaded, !loading else { return }
        checking = true; cancelled = false; findings = []; failures = []; checked = 0; checkedAt = nil
        let candidates = applications, mappings = repositories, appStore = includeAppStore, prereleases = includePrereleases
        let task = Task { [weak self] in
            guard let self else { return }
            defer { checking = false; self.task = nil }
            do {
                var settings = ApplicationUpdateSettings(); settings.includePrereleases = prereleases
                for source: ApplicationUpdateSource in appStore ? [.sparkle, .appStore] : [.sparkle] {
                    let result = try await scanner.check(source, applications: candidates.filter { mappings[$0.bundleID] == nil }, settings: settings) { _,_ in }
                    try Task.checkCancellation()
                    checked += result.checked; failures += result.failures
                    findings += result.findings.map { finding in
                        let url = finding.release.storeID.flatMap { URL(string: "macappstore://apps.apple.com/app/id\($0)") }
                        return .init(app: finding.app, installed: finding.installedVersion, available: finding.availableVersion, source: source.localizedTitle, releaseURL: url)
                    }
                }
                var releasesByRepository: [GitHubRepository:[GitHubApplicationRelease]] = [:]
                for app in candidates {
                    try Task.checkCancellation()
                    guard let raw = mappings[app.bundleID], let repository = GitHubRepository(raw) else { continue }
                    guard !app.version.isEmpty, app.version != "—" else { failures.append(app.name + ": " + String(localized: "Kurulu sürüm okunamadı."));continue }
                    do {
                        let releases: [GitHubApplicationRelease]
                        if let cached = releasesByRepository[repository] { releases = cached }
                        else {
                            let data = try await ApplicationUpdateHTTP.fetch(repository.apiURL)
                            releases = try GitHubReleaseCatalog.decode(data, repository: repository, includePrereleases: prereleases)
                            releasesByRepository[repository] = releases
                        }
                        try Task.checkCancellation()
                        guard !releases.isEmpty else { failures.append(app.name + ": " + String(localized: "Karşılaştırılabilir sürüm bulunamadı.")); continue }
                        checked += 1
                        let available = releases.filter { comparator.compareVersion($0.version, toVersion: app.version) == .orderedDescending }
                        if let release = available.max(by: { comparator.compareVersion($0.version, toVersion: $1.version) == .orderedAscending }) {
                            findings.append(.init(app: app, installed: app.version, available: release.version, source: "GitHub · " + repository.slug, releaseURL: release.url))
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch { try Task.checkCancellation(); failures.append(app.name + ": " + error.localizedDescription) }
                }
                checkedAt = Date()
            } catch { if Task.isCancelled { cancelled = true } else { failures.append(error.localizedDescription) } }
        }
        self.task = task; await task.value
    }
    func cancel() { task?.cancel() }
    func open(_ finding: IndependentUpdateFinding) {
        if let url = finding.releaseURL { NSWorkspace.shared.open(url) }
        else { NSWorkspace.shared.openApplication(at: finding.app.url, configuration: .init()) }
    }
}
