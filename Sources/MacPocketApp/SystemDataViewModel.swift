import AppKit
import MacPocketCore
import Observation
import SwiftUI

/// Opens Disk Röntgeni from a notification, remembering which tab it should show.
@MainActor
enum SystemDataRouting {
    nonisolated static let notificationPrefix = "MacPocket.systemData."
    private(set) static var requestedTab: SystemDataViewModel.Tab?

    static func open(tab rawValue: String?) {
        requestedTab = rawValue.flatMap(SystemDataViewModel.Tab.init(rawValue:))
        let model = PocketApplicationState.shared.model
        model.openMainWindow?()
        model.navigation.open(.systemData)
    }

    /// The tab a notification asked for, once; nil when the page was opened normally.
    static func consumeRequestedTab() -> SystemDataViewModel.Tab? {
        defer { requestedTab = nil }
        return requestedTab
    }
}

/// State and actions of the Disk Röntgeni page. Measuring and removing happen in the Core actors; this class
/// only holds what the page shows and turns clicks into those calls.
@MainActor
@Observable
final class SystemDataViewModel {
    enum Phase: Equatable { case idle, scanning(String), ready }
    enum Tab: String, CaseIterable, Identifiable {
        case items, projects, history, automation
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case size, idle, name
        var id: String { rawValue }
    }

    /// The page's one model. Pages are rebuilt on every visit; a model per view started a fresh full-disk
    /// scan each time and left the previous one running, so a few visits stacked several scans and froze the
    /// app.
    static let shared = SystemDataViewModel()

    static let rememberChangesKey = "MacPocket.systemData.rememberChanges"
    static let uiStateKey = "MacPocket.systemData.uiState"
    static let hiddenKey = "MacPocket.systemData.hidden"
    static let freeUpSizes = [5, 10, 20, 50, 100]

    private(set) var phase = Phase.idle
    private(set) var items: [SystemDataItem] = []
    private(set) var report: SystemDataReport?
    private(set) var history = SystemDataHistory()
    private(set) var hiddenIDs: Set<String>
    private(set) var breakdowns: [String: [SystemDataBreakdownEntry]] = [:]
    private(set) var removing = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var freeUpNote: String?
    private(set) var archives: [SystemDataArchiveRecord] = []
    private(set) var archivingID: String?
    private(set) var shrinkingID: String?
    private(set) var scanProgress: SystemDataScanProgress?
    /// True after a permanent removal whose space did not come back: local snapshots probably still hold it.
    private(set) var snapshotsMayHoldSpace = false

    /// Changing the selection while a confirmation is open withdraws it: what was reviewed is no longer what
    /// is selected.
    var selection: Set<String> = [] { didSet { if selection != oldValue, pendingPreview != nil { pendingPreview = nil } } }
    /// The page remembers how it was left: which groups were open, how the list is sorted, which tab was
    /// showing.
    var expandedGroups: Set<SystemDataGroup> = [] { didSet { if expandedGroups != oldValue { saveUIState() } } }
    var expandedItems: Set<String> = []
    var filter = ""
    var sort = Sort.size { didSet { if sort != oldValue { saveUIState() } } }
    var tab = Tab.items { didSet { if tab != oldValue { saveUIState() } } }
    var pendingPreview: SystemDataRemovalPreview?

    @ObservationIgnored private let scanner: SystemDataScanner
    @ObservationIgnored private let remover: SystemDataRemover
    @ObservationIgnored private let archiver: SystemDataArchiver
    @ObservationIgnored private let shrinker: SystemDataShrinker
    @ObservationIgnored private let store: SystemDataHistoryStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let environment: SystemDataEnvironment
    @ObservationIgnored private let removalMode: () -> RemovalMode
    @ObservationIgnored private let summaryFile: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// Tests and the runtime audit pass a fixture environment and remover; the app uses the live ones.
    init(defaults: UserDefaults = .standard, store: SystemDataHistoryStore = SystemDataHistoryStore(),
         environment: SystemDataEnvironment = SystemDataViewModel.liveEnvironment, remover: SystemDataRemover = SystemDataViewModel.liveRemover,
         archiver: SystemDataArchiver = SystemDataArchiver(), shrinker: SystemDataShrinker = SystemDataShrinker(),
         removalMode: @escaping () -> RemovalMode = { RemovalModePreference.load() },
         summaryFile: URL? = SystemDataSummary.fileURL) {
        self.defaults = defaults
        self.environment = environment
        self.removalMode = removalMode
        self.summaryFile = summaryFile
        self.store = store
        hiddenIDs = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
        scanner = SystemDataScanner(environment: environment)
        self.remover = remover
        self.archiver = archiver
        self.shrinker = shrinker
        restoreUIState()
    }

    static var liveEnvironment: SystemDataEnvironment {
        SystemDataEnvironment(includeExternalProjects: SystemDataExternalVolumes.isEnabled(), installedAppName: { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path) }
        })
    }

    static var liveRemover: SystemDataRemover {
        SystemDataRemover(runningAppName: { id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }?.localizedName
        })
    }

    private struct UIState: Codable { var tab: String; var sort: String; var expandedGroups: [String] }

    private func saveUIState() {
        let state = UIState(tab: tab.rawValue, sort: sort.rawValue, expandedGroups: expandedGroups.map(\.rawValue).sorted())
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.uiStateKey) }
    }

    private func restoreUIState() {
        guard let data = defaults.data(forKey: Self.uiStateKey), let state = try? JSONDecoder().decode(UIState.self, from: data) else { return }
        tab = Tab(rawValue: state.tab) ?? .items
        sort = Sort(rawValue: state.sort) ?? .size
        expandedGroups = Set(state.expandedGroups.compactMap(SystemDataGroup.init(rawValue:)))
    }

    var rememberChanges: Bool {
        defaults.object(forKey: Self.rememberChangesKey) as? Bool ?? true
    }

    var isScanning: Bool { if case .scanning = phase { true } else { false } }

    // MARK: Scanning

    func startScan() {
        guard !isScanning else { return }
        errorMessage = nil
        statusMessage = nil
        freeUpNote = nil
        phase = .scanning(String(localized: "Taramaya hazırlanıyor…"))
        scanProgress = nil
        items = []
        scanTask = Task { [weak self] in
            guard let self else { return }
            let hidden = hiddenIDs
            if rememberChanges { history = await store.load() }
            for await event in scanner.scan(hidden: hidden) {
                switch event {
                case .phase(let text): phase = .scanning(text)
                case .progress(let reading): scanProgress = reading
                case .item(let item): items.append(item)
                case .finished(let finished): await finish(finished)
                }
            }
            if isScanning { phase = .ready }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        Task { await scanner.cancel() }
    }

    private func finish(_ finished: SystemDataReport) async {
        scanProgress = nil
        report = finished
        items = finished.items
        SystemDataSummary(report: finished).save(to: defaults, file: summaryFile)
        selection.formIntersection(Set(items.map(\.id)))
        if rememberChanges, !Task.isCancelled {
            do { history = try await store.update { $0.record(finished) } }
            catch { errorMessage = error.localizedDescription }
        }
        phase = .ready
    }

    // MARK: Derived lists

    /// Items matching the search field. Selection survives the filter; `selectedOffScreenCount` says how many
    /// it hides.
    var visibleItems: [SystemDataItem] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { SystemDataSearch.matches(query, item: $0) }
    }

    var groups: [(group: SystemDataGroup, items: [SystemDataItem], bytes: Int64)] {
        let byGroup = Dictionary(grouping: visibleItems.filter { $0.group != .projects }, by: \.group)
        return byGroup.map { group, members in
            (group, sorted(members), members.reduce(0) { $0 + $1.sizeBytes })
        }.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.group.rawValue < $1.group.rawValue }
    }

    var projects: [(path: String, name: String, items: [SystemDataItem], bytes: Int64, idleDays: Int?)] {
        let now = Date()
        let byProject = Dictionary(grouping: visibleItems.filter { $0.group == .projects && $0.projectPath != nil }, by: { $0.projectPath! })
        return byProject.map { path, members in
            let newest = members.compactMap(\.lastActivity).max()
            return (path, URL(fileURLWithPath: path).lastPathComponent, members.sorted { $0.sizeBytes > $1.sizeBytes },
                    members.reduce(0) { $0 + $1.sizeBytes }, newest.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) })
        }.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
    }

    private func sorted(_ members: [SystemDataItem]) -> [SystemDataItem] {
        switch sort {
        case .size: members.sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id }
        case .idle: members.sorted { ($0.idleDays() ?? -1) != ($1.idleDays() ?? -1) ? ($0.idleDays() ?? -1) > ($1.idleDays() ?? -1) : $0.id < $1.id }
        case .name: members.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var largestGroupBytes: Int64 { groups.map(\.bytes).max() ?? 0 }
    var selectedItems: [SystemDataItem] { items.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var selectedOffScreenCount: Int {
        let visible = Set(visibleItems.map(\.id))
        return selection.subtracting(visible).count
    }
    var growthAlerts: [SystemDataGrowthAlert] { history.growthAlerts() }
    var returnedItems: [SystemDataReturnedItem] { history.returnedItems(current: items) }

    func change(of item: SystemDataItem) -> Int64? {
        history.change(forItem: item.id, currentBytes: item.sizeBytes, overDays: 7)
    }

    func trend(of item: SystemDataItem) -> [Double] {
        history.trend(forItem: item.id).map(Double.init)
    }

    var weeklyChange: Int64? {
        guard let report else { return nil }
        return history.totalChange(currentBytes: report.systemDataBytes, overDays: 7)
    }

    // MARK: Selection

    func toggle(_ item: SystemDataItem) {
        guard item.isRemovable else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func toggleProject(_ members: [SystemDataItem]) {
        let ids = Set(members.map(\.id))
        if ids.isSubset(of: selection) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    /// Ticks every removable Safe item on screen, or unticks them when they already are.
    func toggleSafe() {
        let safe = Set(visibleItems.filter { $0.safety == .safe && $0.isRemovable && $0.sizeBytes > 0 }.map(\.id))
        guard !safe.isEmpty else { return }
        if safe.isSubset(of: selection) { selection.subtract(safe) } else { selection.formUnion(safe) }
        freeUpNote = nil
    }

    func selectIdleProjects(days: Int = 60) {
        let idle = items.filter { $0.group == .projects && ($0.idleDays() ?? 0) >= days }.map(\.id)
        selection.formUnion(idle)
    }

    func clearSelection() { selection = []; freeUpNote = nil }

    /// What the one-tap button removes: Safe items that need no password, with their apps closed.
    var cleanableNow: [SystemDataItem] {
        SystemDataAutoClean.eligible(items, runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                                     home: environment.home, temporaryDirectory: environment.temporaryDirectory)
    }

    /// One tap from the overview: select exactly the cleanable Safe items and show the confirmation with
    /// every command.
    func cleanSafeNow() {
        let ids = Set(cleanableNow.map(\.id))
        guard !ids.isEmpty else { return }
        selection = ids
        freeUpNote = nil
        requestRemoval()
    }

    /// Reads the disk again so "free space" moves as soon as something was removed, without a new scan.
    private func refreshCapacity() {
        guard let current = report else { return }
        let capacity = environment.capacity()
        report = SystemDataReport(scannedAt: current.scannedAt, items: items, totalBytes: capacity?.totalBytes ?? current.totalBytes,
                                  freeBytes: capacity?.availableBytes ?? current.freeBytes,
                                  purgeableBytes: capacity?.purgeableBytes ?? current.purgeableBytes,
                                  complete: current.complete, unreadablePlaces: current.unreadablePlaces)
        if let report { SystemDataSummary(report: report).save(to: defaults, file: summaryFile) }
    }

    var unreadablePlaces: Int { report?.unreadablePlaces ?? 0 }

    /// A permanent removal of at least 100 MB that returned under half of it: something else is still holding
    /// the blocks (APFS local snapshots keep deleted files until they expire). Moving to the Trash frees
    /// nothing by design, so it never counts.
    static func spaceDidNotComeBack(mode: RemovalMode, freedBytes: Int64, freeBefore: Int64?, freeAfter: Int64?) -> Bool {
        guard mode == .deletePermanently, freedBytes >= 100_000_000, let freeBefore, let freeAfter, freeBefore > 0, freeAfter > 0 else { return false }
        return freeAfter - freeBefore < freedBytes / 2
    }

    func dismissSnapshotNotice() { snapshotsMayHoldSpace = false }

    /// Opens the confirmation for the local snapshots, with the same commands and the same choice as any
    /// other removal.
    func removeSnapshots() {
        let snapshots = items.filter { $0.group == .snapshots }
        guard !snapshots.isEmpty else { return }
        snapshotsMayHoldSpace = false
        selection = Set(snapshots.map(\.id))
        requestRemoval()
    }

    func freeUp(gigabytes: Int) {
        let plan = FreeUpPlanner.plan(items: items, targetBytes: Int64(gigabytes) * 1_000_000_000)
        selection = Set(plan.selectedIDs)
        let size = ByteCountFormatter.string(fromByteCount: plan.selectedBytes, countStyle: .file)
        if plan.reachesTarget {
            freeUpNote = plan.includesReview
                ? String(localized: "\(gigabytes) GB için \(plan.selectedIDs.count) öğe seçildi (\(size)); Güvenli olanlar yetmediği için bazı “İncele” öğeleri de dahil.")
                : String(localized: "\(gigabytes) GB için yalnızca Güvenli \(plan.selectedIDs.count) öğe seçildi (\(size)).")
        } else {
            let short = ByteCountFormatter.string(fromByteCount: plan.shortfallBytes, countStyle: .file)
            freeUpNote = String(localized: "Her şeyi silsen bile \(gigabytes) GB’a \(short) yetmiyor; yalnızca Güvenli öğeler seçildi (\(size)).")
        }
    }

    // MARK: Hiding and breakdown

    func hide(_ item: SystemDataItem) {
        hiddenIDs.insert(item.id)
        defaults.set(hiddenIDs.sorted(), forKey: Self.hiddenKey)
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
    }

    func unhideAll() {
        hiddenIDs = []
        defaults.removeObject(forKey: Self.hiddenKey)
        startScan()
    }

    func loadBreakdown(for item: SystemDataItem) async {
        guard breakdowns[item.id] == nil, !item.paths.isEmpty else { return }
        breakdowns[item.id] = await SystemDataBreakdown.topEntries(of: item.paths)
    }

    func reveal(_ item: SystemDataItem) {
        let urls = item.paths.map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    // MARK: Removal

    func requestRemoval(of subset: [SystemDataItem]? = nil) {
        let chosen = (subset ?? selectedItems).filter(\.isRemovable)
        guard !chosen.isEmpty, !removing else { return }
        pendingPreview = SystemDataRemovalPlanner.preview(items: chosen, mode: removalMode(), home: environment.home,
                                                          temporaryDirectory: environment.temporaryDirectory)
    }

    func cancelRemoval() { pendingPreview = nil }

    func confirmRemoval() async {
        guard let preview = pendingPreview, !removing else { return }
        pendingPreview = nil
        removing = true
        errorMessage = nil
        statusMessage = nil
        defer { removing = false }
        let ids = Set(preview.lines.map(\.id))
        let chosen = items.filter { ids.contains($0.id) }
        let prompt = String(localized: "MacPocket seçtiğin sistem verisini kaldırmak için yönetici izni istiyor.")
        let outcomes = await remover.remove(chosen, mode: preview.mode, administratorPrompt: prompt)
        let succeeded = outcomes.filter(\.succeeded)
        let failed = outcomes.filter { !$0.succeeded }

        let now = Date()
        let byID = Dictionary(chosen.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if rememberChanges, !succeeded.isEmpty {
            let records = succeeded.compactMap { outcome in
                byID[outcome.itemID].map { SystemDataDeletionRecord(date: now, itemID: $0.id, title: $0.title, bytes: $0.sizeBytes, paths: $0.paths) }
            }
            if let updated = try? await store.update({ history in records.forEach { history.recordDeletion($0) } }) { history = updated }
        }
        let gone = Set(succeeded.map(\.itemID))
        items.removeAll { gone.contains($0.id) }
        selection.subtract(gone)
        let freed = succeeded.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let freedText = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
        let freeBefore = report?.freeBytes
        refreshCapacity()
        snapshotsMayHoldSpace = Self.spaceDidNotComeBack(mode: preview.mode, freedBytes: freed, freeBefore: freeBefore, freeAfter: report?.freeBytes)
            && items.contains { $0.group == .snapshots }
        statusMessage = preview.mode == .moveToTrash
            ? String(localized: "\(succeeded.count) öğe Çöp’e taşındı (\(freedText)); alan Çöp boşaltılınca geri gelir.")
            : String(localized: "\(succeeded.count) öğe kaldırıldı; \(freedText) boşaldı.")
        if let first = failed.first {
            errorMessage = failed.count == 1
                ? "\(first.title): \(first.error ?? "")"
                : String(localized: "\(failed.count) öğe kaldırılamadı. İlki: \(first.title): \(first.error ?? "")")
        }
    }

    // MARK: Shrink

    /// Stores the item's folders compressed in place. Nothing is deleted and every path keeps working.
    func shrink(_ subset: [SystemDataItem]) async {
        let chosen = subset.filter(\.isShrinkable)
        guard !chosen.isEmpty, shrinkingID == nil, archivingID == nil else { return }
        errorMessage = nil
        statusMessage = nil
        var saved: Int64 = 0, done = 0
        var firstProblem: String?
        for item in chosen {
            shrinkingID = item.id
            var itemSaved: Int64 = 0
            for path in item.paths {
                do { itemSaved += try await shrinker.shrink(folder: path, guardRoot: item.projectPath).savedBytes }
                catch { firstProblem = firstProblem ?? "\(item.title): \(error.localizedDescription)" }
            }
            if itemSaved > 0, let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = items[index].resized(to: max(0, items[index].sizeBytes - itemSaved))
                saved += itemSaved
                done += 1
            }
        }
        shrinkingID = nil
        refreshCapacity()
        if done > 0 {
            statusMessage = String(localized: "\(done) öğe sıkıştırıldı; \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) kazanıldı. Hiçbir şey silinmedi, tüm yollar çalışmaya devam ediyor.")
        }
        errorMessage = firstProblem
    }

    // MARK: Archives

    func loadArchives() async { archives = await archiver.records() }

    /// Packs the given folders into verified archives, one after another, and drops them from the list once
    /// safe.
    func archive(_ subset: [SystemDataItem]) async {
        let chosen = subset.filter(\.isArchivable)
        guard !chosen.isEmpty, archivingID == nil else { return }
        errorMessage = nil
        statusMessage = nil
        var saved: Int64 = 0, done = 0
        for item in chosen {
            archivingID = item.id
            if let name = item.busyBundleIDs.first { errorMessage = name; break }
            do {
                let record = try await archiver.archive(folder: item.paths[0], title: item.title)
                saved += record.savedBytes
                done += 1
                items.removeAll { $0.id == item.id }
                selection.remove(item.id)
            } catch {
                errorMessage = "\(item.title): \(error.localizedDescription)"
                break
            }
        }
        archivingID = nil
        refreshCapacity()
        archives = await archiver.records()
        if done > 0 {
            statusMessage = String(localized: "\(done) klasör arşivlendi; \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) kazanıldı. Gerektiğinde “Arşivler”den geri yükleyebilirsin.")
        }
    }

    func restore(_ record: SystemDataArchiveRecord) async {
        errorMessage = nil
        do { try await archiver.restore(record); statusMessage = String(localized: "“\(record.title)” geri yüklendi.") }
        catch { errorMessage = "\(record.title): \(error.localizedDescription)" }
        archives = await archiver.records()
    }

    func deleteArchive(_ record: SystemDataArchiveRecord) async {
        errorMessage = nil
        do { try await archiver.deleteArchive(record) } catch { errorMessage = "\(record.title): \(error.localizedDescription)" }
        archives = await archiver.records()
    }

    // MARK: History

    func eraseHistory() async {
        try? await store.erase()
        history = SystemDataHistory()
    }

    func setRememberChanges(_ remember: Bool) async {
        defaults.set(remember, forKey: Self.rememberChangesKey)
        if remember { history = await store.load() } else { await eraseHistory() }
    }
}
