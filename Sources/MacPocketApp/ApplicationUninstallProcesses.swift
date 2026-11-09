import AppKit
import Combine
import MacPocketCore

struct UninstallRunningProcess: Identifiable, Equatable, Sendable {
    let pid: Int32
    let name: String
    let entry: ProcessEntry?
    let isMainApplication: Bool
    var id: Int32 { pid }
    var canStop: Bool { entry?.canTerminate == true }
    var identity: ProcessIdentity? { entry?.identity }
}

@MainActor protocol UninstallProcessManaging {
    func inspect(_ application: InstalledApplication, validateBundle: Bool) async throws -> [UninstallRunningProcess]
    func quit(_ process: UninstallRunningProcess, application: InstalledApplication, force: Bool) async throws
}

@MainActor final class ApplicationUninstallProcesses: UninstallProcessManaging {
    private let monitor = ProcessMonitor()
    func inspect(_ application: InstalledApplication, validateBundle: Bool = true) async throws -> [UninstallRunningProcess] {
        if validateBundle { try UninstallPlanner.validateApplication(application) }
        let snapshot = try await monitor.snapshot()
        try Task.checkCancellation()
        let root = application.url.resolvingSymlinksInPath().standardizedFileURL.path
        let executable = Bundle(url: application.url)?.executableURL?.resolvingSymlinksInPath().standardizedFileURL.path
        let workspace = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        var matches: [Int32: UninstallRunningProcess] = [:]
        for entry in snapshot.processes where UninstallProcessScope.contains(entry.command, applicationURL: application.url) {
            let gui = workspace.first { $0.processIdentifier == entry.pid }
            let main = gui?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == root || entry.command == executable
            matches[entry.pid] = .init(pid: entry.pid, name: gui?.localizedName ?? entry.name, entry: entry, isMainApplication: main)
        }
        for gui in workspace {
            let path = gui.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
            let exact = path == root
            // A translocated/unknown path with the same ID cannot be safely attributed or stopped.
            let ambiguous = gui.bundleIdentifier == application.bundleID && (path == nil || path?.contains("/AppTranslocation/") == true)
            guard matches[gui.processIdentifier] == nil, exact || ambiguous else { continue }
            matches[gui.processIdentifier] = .init(pid: gui.processIdentifier, name: gui.localizedName ?? application.name,
                                                   entry: nil, isMainApplication: true)
        }
        return matches.values.sorted { lhs, rhs in
            if lhs.isMainApplication != rhs.isMainApplication { return lhs.isMainApplication }
            return lhs.pid < rhs.pid
        }
    }
    func quit(_ process: UninstallRunningProcess, application: InstalledApplication, force: Bool) async throws {
        let fresh = try await inspect(application, validateBundle: true)
        guard let current = fresh.first(where: { $0.pid == process.pid }) else { return }
        guard let entry = current.entry, entry.identity == process.identity, current.canStop else {
            throw ProcessMonitorError.identityChanged(process.pid)
        }
        if !force, !current.isMainApplication, fresh.contains(where: \.isMainApplication) {
            throw NSError(domain: "MacPocket.Uninstall", code: 2, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Ana uygulama hâlâ açık; yardımcı süreçler kapatılmadı.")])
        }
        try Task.checkCancellation()
        if !force, let gui = NSRunningApplication(processIdentifier: process.pid), !gui.isTerminated,
           let url = gui.bundleURL,
           url.resolvingSymlinksInPath().standardizedFileURL.path == application.url.resolvingSymlinksInPath().standardizedFileURL.path ||
            UninstallProcessScope.contains(url.path, applicationURL: application.url) {
            // AppKit delivers the normal quit request, allowing document save/cancel panels.
            guard gui.terminate() || gui.isTerminated else {
                throw NSError(domain: "MacPocket.Uninstall", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: String(localized: "\(process.name) kapatma isteğini kabul etmedi.")])
            }
        } else {
            guard force || !current.isMainApplication else {
                throw NSError(domain: "MacPocket.Uninstall", code: 4, userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "Uygulamanın normal çıkış bağlantısı doğrulanamadı. Elle kapatıp yeniden dene.")])
            }
            try await monitor.terminate(entry: entry, force: force)
        }
    }
}

@MainActor final class UninstallPreparationModel: ObservableObject {
    @Published private(set) var processes: [UninstallRunningProcess] = []
    @Published private(set) var busy = false
    @Published private(set) var checked = false
    @Published private(set) var attemptedQuit = false
    @Published private(set) var failure: String?
    private let application: InstalledApplication
    private let service: any UninstallProcessManaging
    private let grace: Duration
    private let interval: Duration
    private var generation = UUID()
    private var work: Task<Bool, Never>?
    init(application: InstalledApplication, service: any UninstallProcessManaging = ApplicationUninstallProcesses(),
         grace: Duration = .seconds(6), interval: Duration = .milliseconds(200)) {
        self.application = application; self.service = service; self.grace = grace; self.interval = interval
    }
    var forceIdentities: Set<ProcessIdentity> { Set(processes.filter(\.canStop).compactMap(\.identity)) }
    var canOfferForce: Bool { attemptedQuit && !busy && !processes.isEmpty && processes.allSatisfy(\.canStop) }
    func refresh() async {
        guard !busy else { return }
        let token = generation
        do {
            let fresh = try await service.inspect(application, validateBundle: true)
            guard generation == token, !Task.isCancelled else { return }
            processes = fresh; checked = true
            if fresh.isEmpty || !attemptedQuit { failure = nil }
        } catch { if generation == token, !Task.isCancelled { failure = error.localizedDescription; checked = false } }
    }
    /// Does not remove files. Only the caller's explicit confirmation may request graceful exit or force.
    func prepare(forceConsent: Set<ProcessIdentity>? = nil) async -> Bool {
        guard !busy else { return false }
        generation = UUID(); let token = generation
        busy = true; failure = nil; attemptedQuit = true
        let task = Task { await performPrepare(forceConsent: forceConsent, token: token) }
        work = task
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    private func performPrepare(forceConsent: Set<ProcessIdentity>?, token: UUID) async -> Bool {
        defer { if generation == token { busy = false; work = nil } }
        do {
            processes = try await service.inspect(application, validateBundle: true); checked = true
            guard generation == token, !Task.isCancelled else { return false }
            if let forceConsent {
                guard processes.allSatisfy({ $0.canStop && $0.identity.map(forceConsent.contains) == true }) else {
                    failure = String(localized: "Süreç listesi değişti veya güvenle kapatılamayan süreç var. Listeyi yeniden incele."); return false
                }
                for process in processes {
                    try Task.checkCancellation(); guard generation == token else { return false }
                    try await service.quit(process, application: application, force: true)
                }
            } else {
                // Keep helpers alive while the main application may still be saving documents.
                for process in processes.filter(\.isMainApplication) where process.canStop {
                    try await service.quit(process, application: application, force: false)
                    guard generation == token, !Task.isCancelled else { return false }
                }
                if processes.contains(where: \.isMainApplication) {
                    guard try await wait(token: token, mainOnly: true) else {
                        if generation == token { failure = String(localized: "Uygulama kapanmadı. Kaydetme penceresini yanıtla; kapandığında yeniden dene.") }
                        return false
                    }
                }
                for process in processes where process.canStop {
                    try await service.quit(process, application: application, force: false)
                    guard generation == token, !Task.isCancelled else { return false }
                }
            }
            guard try await wait(token: token, mainOnly: false) else {
                if generation == token { failure = String(localized: "Bazı süreçler hâlâ çalışıyor. Dosyalar kaldırılmadı; yeniden dene veya ayrı onayla zorla kapat.") }
                return false
            }
            return generation == token && !Task.isCancelled
        } catch {
            if generation == token, !Task.isCancelled { failure = error.localizedDescription }
            return false
        }
    }
    private func wait(token: UUID, mainOnly: Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + grace
        while generation == token && !Task.isCancelled {
            let fresh = try await service.inspect(application, validateBundle: true)
            guard generation == token, !Task.isCancelled else { return false }
            processes = fresh
            if mainOnly ? !fresh.contains(where: \.isMainApplication) : fresh.isEmpty { return true }
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: interval)
        }
        return false
    }
    func cancel() { generation = UUID(); work?.cancel(); work = nil; busy = false }
}
