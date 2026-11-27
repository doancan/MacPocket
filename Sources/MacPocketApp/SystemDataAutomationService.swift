import AppKit
import MacPocketCore
import UserNotifications

/// Runs the opt-in background work of Disk Röntgeni: the daily scan, its alerts and the weekly clean of Safe
/// items. `tick()` is cheap and is called from the existing monitoring loop; a scan starts only when one is
/// due.
@MainActor
final class SystemDataAutomationService {
    static let shared = SystemDataAutomationService()

    /// How often `tick()` re-reads the settings; the scan itself is due at most once a day.
    private static let checkInterval: TimeInterval = 600

    private let defaults: UserDefaults
    private let store: SystemDataHistoryStore
    private var running = false
    private var lastCheck = Date.distantPast

    init(defaults: UserDefaults = .standard, store: SystemDataHistoryStore = SystemDataHistoryStore()) {
        self.defaults = defaults
        self.store = store
    }

    func tick(now: Date = Date()) {
        guard !running, now.timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
        lastCheck = now
        let settings = SystemDataAutomationSettings.load(from: defaults)
        let state = SystemDataAutomationState.load(from: defaults)
        guard SystemDataAutomationPolicy.isScanDue(settings, state: state, now: now) else { return }
        running = true
        Task { [weak self] in
            await self?.runScan(settings: settings)
            self?.running = false
        }
    }

    private func runScan(settings: SystemDataAutomationSettings) async {
        let hidden = Set(defaults.stringArray(forKey: SystemDataViewModel.hiddenKey) ?? [])
        let scanner = SystemDataScanner(environment: SystemDataViewModel.liveEnvironment)
        var finished: SystemDataReport?
        for await event in scanner.scan(hidden: hidden) { if case .finished(let report) = event { finished = report } }
        guard let report = finished, report.complete else { return }
        SystemDataSummary(report: report).save(to: defaults, file: SystemDataSummary.fileURL)

        let remember = defaults.object(forKey: SystemDataViewModel.rememberChangesKey) as? Bool ?? true
        var history = await store.load()
        if remember, let updated = try? await store.update({ $0.record(report) }) { history = updated }

        var state = SystemDataAutomationState.load(from: defaults)
        let actions = SystemDataAutomationPolicy.decide(settings: settings, state: &state, report: report, history: history,
                                                        watching: false, now: Date())
        for action in actions { await perform(action, report: report, state: &state, remember: remember) }
        state.save(to: defaults)
    }

    private func perform(_ action: SystemDataAutomationAction, report: SystemDataReport,
                         state: inout SystemDataAutomationState, remember: Bool) async {
        func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        switch action {
        case .lowSpace(let free, let safe):
            await notify(id: "lowSpace", title: String(localized: "Disk alanı azaldı"),
                         body: String(localized: "Başlangıç diskinde yalnız \(size(free)) boş alan kaldı. Disk Röntgeni’nde şu an \(size(safe)) güvenle boşaltılabilir."))
        case .growth(let alert):
            await notify(id: "growth." + alert.group.rawValue, title: String(localized: "Sistem Verisi olağandışı büyüdü"),
                         body: String(localized: "“\(alert.group.localizedTitle)” olağan \(size(alert.medianBytes)) boyutundan \(size(alert.currentBytes)) boyutuna çıktı."),
                         tab: .history)
            if remember { _ = try? await store.update { $0.markAlerted(alert) } }
        case .weeklySummary(let change, let group):
            let detail = group.map { String(localized: "En çok büyüyen: \($0.localizedTitle).") } ?? ""
            await notify(id: "weekly", title: String(localized: "Haftalık Sistem Verisi özeti"),
                         body: String(localized: "Sistem Verisi bu hafta \(size(change)) büyüdü. \(detail)"), tab: .history)
        case .autoClean:
            await autoClean(report: report, state: &state, remember: remember)
        }
    }

    /// Safe items that need no password, and only while their owning apps are closed.
    private func autoClean(report: SystemDataReport, state: inout SystemDataAutomationState, remember: Bool) async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let items = SystemDataAutoClean.eligible(report.items, runningBundleIDs: running)
        state.lastAutoClean = Date()
        guard !items.isEmpty else { return }
        let outcomes = await SystemDataViewModel.liveRemover.remove(items, mode: RemovalModePreference.load(),
                                                                    administratorPrompt: String(localized: "MacPocket yönetici izni istiyor."))
        let done = outcomes.filter(\.succeeded)
        guard !done.isEmpty else { return }
        let freed = done.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if remember {
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let now = Date()
            let records = done.compactMap { outcome in
                byID[outcome.itemID].map { SystemDataDeletionRecord(date: now, itemID: $0.id, title: $0.title, bytes: $0.sizeBytes, paths: $0.paths) }
            }
            _ = try? await store.update { history in records.forEach { history.recordDeletion($0) } }
        }
        await notify(id: "autoClean", title: String(localized: "Otomatik temizlik tamamlandı"),
                     body: String(localized: "\(done.count) güvenli öğe kaldırıldı; \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) boşaldı."))
    }

    private func notify(id: String, title: String, body: String, tab: SystemDataViewModel.Tab = .items) async {
        guard PocketAlertNotifier.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["tab": tab.rawValue]
        try? await center.add(UNNotificationRequest(identifier: SystemDataRouting.notificationPrefix + id, content: content, trigger: nil))
    }
}
