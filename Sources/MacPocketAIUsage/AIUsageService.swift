import Combine
import Foundation
import MacPocketCore
import UsageCore

public struct AIUsageNotice: Sendable {
    public let accountID: UUID
    public let accountName: String
    public let limit: UsageLimit
    public let level: AlertLevel
}

/// Each account has its own board, request timestamps, backoff and alert window. ProviderID alone
/// is never used as the account key: two Claude accounts cannot replace one another's readings.
@MainActor
public final class AIUsageService: ObservableObject {
    public static let shared: AIUsageService = {
        #if DEBUG
        if AIUsageFixtures.requested { return AIUsageFixtures.makeService() }
        #endif
        return AIUsageService()
    }()
    public typealias ProviderFactory = @Sendable (AIUsageAccount, Double, Double) -> any UsageProvider
    @Published public private(set) var settings: AIUsageSettings
    @Published public private(set) var boards: [UUID: UsageBoard]
    @Published public private(set) var refreshing: Set<UUID> = []
    @Published public private(set) var active = false
    @Published public private(set) var storageError: String?
    public var onAlerts: (([AIUsageNotice]) -> Void)?
    private let defaults: UserDefaults
    private let cacheURL: URL?
    private let factory: ProviderFactory
    private var providers: [UUID: any UsageProvider] = [:]
    private var attempts: [UUID: Date] = [:]
    private var alertStates: [UUID: NotificationState] = [:]
    private var generation = UUID()
    private var inFlight: Task<Void, Never>?
    private var inFlightID: UUID?
    private var polling: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?

    public init(defaults: UserDefaults = .standard,
                cacheURL: URL? = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/MacPocket/AIUsage/accounts.json"),
                factory: @escaping ProviderFactory = AIUsageProviderFactory.make) {
        self.defaults = defaults; self.cacheURL = cacheURL; self.factory = factory
        let loaded = AIUsageSettings.load(from: defaults)
        settings = loaded
        let cache = cacheURL.flatMap { url -> Cache? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Cache.self, from: data)
        }
        let sourceIDs = Dictionary(uniqueKeysWithValues: loaded.accounts.map { ($0.id, $0.source.cacheIdentity) })
        boards = cache?.boards.filter { cache?.sources[$0.key] == sourceIDs[$0.key] && sourceIDs[$0.key] != nil } ?? [:]
        alertStates = cache?.alerts.filter { cache?.sources[$0.key] == sourceIDs[$0.key] && sourceIDs[$0.key] != nil } ?? [:]
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadSettings() }
            }
    }

    public var enabledAccounts: [AIUsageAccount] { settings.accounts.filter(\.enabled) }
    public func snapshot(for account: AIUsageAccount) -> UsageSnapshot? { boards[account.id]?.snapshot(for: account.provider.providerID) }
    public func snapshot(for id: UUID) -> UsageSnapshot? {
        settings.accounts.first { $0.id == id }.flatMap(snapshot(for:))
    }

    public func setEnabled(_ value: Bool) {
        guard active != value else { return }
        active = value
        restart()
    }

    public func stop() { setEnabled(false) }

    public func setSettings(_ proposed: AIUsageSettings) {
        let value = proposed.normalized
        guard value != settings else { return }
        let old = settings
        settings = value
        settings.save(to: defaults)
        reconcile(old: old)
    }

    public func add(_ account: AIUsageAccount) -> Bool {
        guard account.source.isValid, !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              settings.accounts.count < 32,
              !settings.accounts.contains(where: { $0.source.identity == account.source.identity || $0.id == account.id }) else { return false }
        var updated = settings; updated.accounts.append(account); setSettings(updated); return true
    }

    public func update(_ account: AIUsageAccount) {
        guard let index = settings.accounts.firstIndex(where: { $0.id == account.id }), account.source.isValid,
              !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.accounts.contains(where: { $0.id != account.id && $0.source.identity == account.source.identity }) else { return }
        var updated = settings; updated.accounts[index] = account; setSettings(updated)
    }

    public func remove(_ id: UUID) {
        var updated = settings; updated.accounts.removeAll { $0.id == id }; setSettings(updated)
    }

    private func reloadSettings() {
        let value = AIUsageSettings.load(from: defaults)
        guard value != settings else { return }
        let old = settings; settings = value; reconcile(old: old)
    }

    private func reconcile(old: AIUsageSettings) {
        let current = Dictionary(uniqueKeysWithValues: settings.accounts.map { ($0.id, $0) })
        for previous in old.accounts where current[previous.id]?.source != previous.source {
            boards[previous.id] = nil; attempts[previous.id] = nil; alertStates[previous.id] = nil
        }
        let previous = Dictionary(uniqueKeysWithValues: old.accounts.map { ($0.id, $0) })
        let accountsChanged = previous.count != current.count || settings.accounts.contains { account in
            guard let before = previous[account.id] else { return true }
            return before.source != account.source || before.enabled != account.enabled
        }
        let requestsChanged = accountsChanged || old.warning != settings.warning
            || old.critical != settings.critical || old.refreshMinutes != settings.refreshMinutes
        persist()
        if requestsChanged { providers = [:]; restart() }
    }

    private func restart() {
        generation = UUID()
        inFlight?.cancel(); inFlight = nil; inFlightID = nil; refreshing = []
        polling?.cancel(); polling = nil
        guard active, !enabledAccounts.isEmpty else { return }
        polling = Task { @MainActor [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                guard let self, active else { break }
                await refresh()
            }
        }
    }

    private func provider(for account: AIUsageAccount) -> any UsageProvider {
        if let provider = providers[account.id] { return provider }
        let provider = factory(account, settings.warning, settings.critical)
        providers[account.id] = provider
        return provider
    }

    public func nextRefresh(for account: AIUsageAccount, manual: Bool = false, now: Date = .now) -> Date {
        let source = provider(for: account)
        let board = boards[account.id] ?? UsageBoard()
        let minimum = UsageRefresher.nextRequestDate(board, provider: source, now: now, manual: manual)
        guard !manual, let attempt = attempts[account.id] else { return minimum }
        return max(minimum, attempt.addingTimeInterval(Double(settings.refreshMinutes * 60)))
    }

    public func refresh(manual: Bool = false, only id: UUID? = nil, now: Date = .now) async {
        guard active else { return }
        if let inFlight { await inFlight.value; return }
        let due = enabledAccounts.filter { (id == nil || $0.id == id) && nextRefresh(for: $0, manual: manual, now: now) <= now }
        guard !due.isEmpty else { return }
        let requests = due.map { account in (account, boards[account.id] ?? UsageBoard(), provider(for: account)) }
        let currentGeneration = generation, token = UUID()
        inFlightID = token; refreshing = Set(due.map(\.id))
        for account in due { attempts[account.id] = now }
        let task = Task { @MainActor [weak self] in
            let results = await withTaskGroup(of: (UUID, UsageBoard).self, returning: [(UUID, UsageBoard)].self) { group in
                for (account, board, provider) in requests {
                    group.addTask {
                        let updated = await UsageRefresher.refresh(board, providers: [provider], now: now, manual: manual)
                        return (account.id, updated)
                    }
                }
                var results: [(UUID, UsageBoard)] = []
                for await result in group { results.append(result) }
                return results
            }
            guard let self, !Task.isCancelled, self.active, self.generation == currentGeneration else { return }
            for (id, board) in results { self.boards[id] = board }
            self.evaluateAlerts(results.map(\.0))
            self.persist()
            if self.inFlightID == token { self.inFlight = nil; self.inFlightID = nil; self.refreshing = [] }
        }
        inFlight = task
        await task.value
    }

    private func evaluateAlerts(_ ids: [UUID]) {
        guard settings.alertsEnabled else { return }
        var notices: [AIUsageNotice] = []
        for account in enabledAccounts where ids.contains(account.id) {
            guard let snapshot = snapshot(for: account), snapshot.status == .ok else { continue }
            var state = alertStates[account.id] ?? NotificationState()
            let crossed = ThresholdEvaluator.evaluate(snapshot, state: &state, warning: settings.warning, critical: settings.critical)
            alertStates[account.id] = state
            // Critical supersedes warning when a reading crosses both at once.
            let criticalIDs = Set(crossed.filter { $0.level == .critical }.map { $0.limit.id })
            notices += crossed.filter { $0.level == .critical || !criticalIDs.contains($0.limit.id) }.map {
                AIUsageNotice(accountID: account.id, accountName: account.name, limit: $0.limit, level: $0.level)
            }
        }
        if !notices.isEmpty { onAlerts?(notices) }
    }

    private struct Cache: Codable { var boards: [UUID: UsageBoard]; var alerts: [UUID: NotificationState]; var sources: [UUID: String] }
    private func persist() {
        guard let cacheURL else { return }
        do {
            let root = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(Cache(boards: boards, alerts: alertStates,
                sources: Dictionary(uniqueKeysWithValues: settings.accounts.map { ($0.id, $0.source.cacheIdentity) })))
            try data.write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            storageError = nil
        } catch { storageError = String(localized: "Kota önbelleği kaydedilemedi; mevcut oturumdaki değerler korunuyor.") }
    }

    public var menuBarReading: MenuBarReading {
        let accounts = enabledAccounts.filter(\.showInMenuBar)
        let selected = Array(accounts.prefix(3))
        let pieces: [(String, String)] = selected.map { account in
            let alias = String(account.name.prefix(6))
            let prefix = account.provider.shortName + ":" + alias
            guard let snapshot = snapshot(for: account), let limit = snapshot.headlineLimit else { return (prefix + " —", prefix + " 100%") }
            let percent = Self.percent(settings.mode.percent(limit.percentUsed))
            return (prefix + " " + percent + (snapshot.status == .ok ? "" : "!"), prefix + " 100%!")
        }
        let suffix = accounts.count > 3 ? " +\(accounts.count - 3)" : ""
        let used = accounts.compactMap { snapshot(for: $0)?.headlineLimit?.percentUsed }.max()
        let text = pieces.isEmpty ? String(localized: "AI Kotaları") : pieces.map(\.0).joined(separator: " · ") + suffix
        let descriptions = enabledAccounts.map { account in
            let quota = snapshot(for: account)?.headlineLimit.map { Self.percent(settings.mode.percent($0.percentUsed)) }
            return account.name + ": " + (quota ?? AIUsageText.status(snapshot(for: account)))
        }
        return MenuBarReading(lines: [text], reserve: [pieces.isEmpty ? text : pieces.map(\.1).joined(separator: " · ") + suffix],
            fraction: used.map { min(1, max(0, $0 / 100)) }, magnitude: used,
            accessibility: String(localized: "AI Kotaları") + ": " + descriptions.joined(separator: "; "), thresholdValue: used)
    }

    public static func percent(_ value: Double) -> String {
        min(100, max(0, value)).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    public func diagnostics() -> String {
        settings.accounts.map { account in
            let count = snapshot(for: account)?.limits.count ?? 0
            return account.provider.localizedTitle + " [" + account.id.uuidString.prefix(8) + "]: "
                + AIUsageText.status(snapshot(for: account)) + " (\(count))"
        }.joined(separator: "\n")
    }

    #if DEBUG
    public func setFixtureBoards(_ fixtures: [UUID: UsageBoard]) { boards = fixtures }
    #endif
}
