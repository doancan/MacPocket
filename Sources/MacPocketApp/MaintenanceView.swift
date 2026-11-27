import MacPocketCore
import SwiftUI

@MainActor
final class MaintenanceModel: ObservableObject {
    let tasks = MaintenanceCatalog.tasks()
    @Published var selected: Set<MaintenanceTaskID>
    @Published private(set) var progress: [MaintenanceTaskID: MaintenanceProgress] = [:]
    @Published private(set) var running = false
    @Published private(set) var lastRun: [MaintenanceTaskID: LastRun] = [:]
    @Published private(set) var summary: RunSummary?
    private var runTask: Task<Void, Never>?

    struct LastRun: Codable, Equatable {
        let date: Date
        let succeeded: Bool
    }

    struct RunSummary: Equatable {
        let succeeded: Int
        let failed: Int
        let skipped: Int
        let seconds: Double
    }

    private static let lastRunKey = "MacPocket.maintenance.lastRun"
    private static let selectionKey = "MacPocket.maintenance.selection"

    init() {
        let available = Set(tasks.filter { $0.support == .ready }.map(\.id))
        if let saved = UserDefaults.standard.stringArray(forKey: Self.selectionKey) {
            selected = Set(saved.compactMap(MaintenanceTaskID.init(rawValue:))).intersection(available)
        } else {
            selected = Set(tasks.filter { $0.recommended && $0.support == .ready }.map(\.id))
        }
        if let data = UserDefaults.standard.data(forKey: Self.lastRunKey),
           let stored = try? JSONDecoder().decode([String: LastRun].self, from: data) {
            lastRun = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
                MaintenanceTaskID(rawValue: key).map { ($0, value) }
            })
        }
    }

    var chosen: [MaintenanceTask] { tasks.filter { selected.contains($0.id) && $0.support == .ready } }
    var chosenNeedsAdministrator: Bool { chosen.contains(where: \.requiresAdministrator) }

    func tasks(in group: MaintenanceGroup) -> [MaintenanceTask] { tasks.filter { $0.group == group } }

    func toggle(_ task: MaintenanceTask) {
        guard task.support == .ready, !running else { return }
        if selected.contains(task.id) { selected.remove(task.id) } else { selected.insert(task.id) }
        saveSelection()
    }

    func select(_ preset: Preset) {
        guard !running else { return }
        let ready = tasks.filter { $0.support == .ready }
        selected = switch preset {
        case .recommended: Set(ready.filter(\.recommended).map(\.id))
        case .all: Set(ready.map(\.id))
        case .none: []
        }
        saveSelection()
    }

    enum Preset { case recommended, all, none }

    func runSelected() { start(chosen) }

    func run(_ task: MaintenanceTask) { start([task]) }

    func cancel() { runTask?.cancel() }

    private func start(_ batch: [MaintenanceTask]) {
        guard !running, !batch.isEmpty else { return }
        running = true
        summary = nil
        progress = [:]
        let started = Date()
        runTask = Task { [weak self] in
            let results = await MaintenanceRunner.run(batch, progress: { id, state in
                await MainActor.run { self?.progress[id] = state }
            })
            guard let self else { return }
            var succeeded = 0, failed = 0, skipped = 0
            for result in results {
                switch result.outcome {
                case .ran:
                    succeeded += 1
                    lastRun[result.task.id] = LastRun(date: Date(), succeeded: true)
                case .failed:
                    failed += 1
                    lastRun[result.task.id] = LastRun(date: Date(), succeeded: false)
                case .skipped: skipped += 1
                }
            }
            saveLastRun()
            summary = RunSummary(succeeded: succeeded, failed: failed, skipped: skipped,
                                 seconds: Date().timeIntervalSince(started))
            running = false
        }
    }

    private func saveSelection() {
        UserDefaults.standard.set(selected.map(\.rawValue).sorted(), forKey: Self.selectionKey)
    }

    private func saveLastRun() {
        let stored = Dictionary(uniqueKeysWithValues: lastRun.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: Self.lastRunKey) }
    }
}

/// Tools → Bakım: small fixes for macOS services, with an honest account of what ran and what was skipped.
struct MaintenanceView: View {
    @StateObject private var model = MaintenanceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Bakım",
                              subtitle: "macOS’un önbellek ve hizmetleri için küçük düzeltmeleri tek seferde çalıştır; neyin çalıştığını ve neyin neden atlandığını gör.",
                              icon: "wrench.and.screwdriver") {
                Menu {
                    Button("Önerilenleri seç") { model.select(.recommended) }
                    Button("Tümünü seç") { model.select(.all) }
                    Button("Seçimi temizle") { model.select(.none) }
                } label: {
                    Label("Seçim", systemImage: "checklist")
                }
                .fixedSize()
                .disabled(model.running)
            }
            runBar
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if let summary = model.summary { summaryMessage(summary) }
                    ForEach(MaintenanceGroup.allCases) { group in
                        let tasks = model.tasks(in: group)
                        if !tasks.isEmpty { groupCard(group, tasks) }
                    }
                    Text("Görevler yalnız macOS’un kendi araçlarını çalıştırır. Yönetici gerektirenler, çalıştırma sırasında tek bir parola sorusunda toplanır.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
    }

    private var runBar: some View {
        HStack(spacing: PocketSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "\(model.chosen.count) görev seçili")).font(.headline)
                Text(model.chosenNeedsAdministrator ? "Bazı görevler yönetici parolası ister." : "Yönetici parolası gerekmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.running {
                ProgressView().controlSize(.small)
                Button("Durdur", role: .cancel) { model.cancel() }
            } else {
                Button { model.runSelected() } label: {
                    Label("Seçilenleri çalıştır", systemImage: "play.fill").padding(.horizontal, PocketSpacing.s)
                }
                .buttonStyle(.pocketPrimary)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.chosen.isEmpty)
            }
        }
        .pocketCard(padding: PocketSpacing.m)
    }

    private func summaryMessage(_ summary: MaintenanceModel.RunSummary) -> some View {
        let text = String(localized: "\(summary.succeeded) başarılı · \(summary.failed) başarısız · \(summary.skipped) atlandı · \(summary.seconds.formatted(.number.precision(.fractionLength(0...1)))) sn")
        return PocketMessage(text, tone: summary.failed > 0 ? .warning : .success)
    }

    private func groupCard(_ group: MaintenanceGroup, _ tasks: [MaintenanceTask]) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader(group.title, icon: group.symbol)
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    MaintenanceTaskRow(task: task, selected: model.selected.contains(task.id), busy: model.running,
                                       progress: model.progress[task.id], lastRun: model.lastRun[task.id],
                                       toggle: { model.toggle(task) }, run: { model.run(task) })
                    if task.id != tasks.last?.id { Divider() }
                }
            }
        }
        .pocketCard()
    }
}

private struct MaintenanceTaskRow: View {
    let task: MaintenanceTask
    let selected: Bool
    let busy: Bool
    let progress: MaintenanceProgress?
    let lastRun: MaintenanceModel.LastRun?
    let toggle: () -> Void
    let run: () -> Void

    private var available: Bool { task.support == .ready }

    var body: some View {
        HStack(alignment: .top, spacing: PocketSpacing.m) {
            Toggle(isOn: Binding(get: { selected }, set: { _ in toggle() })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(busy || !available)
                .accessibilityLabel(Text(task.title))
            Image(systemName: task.symbol).font(.title3).frame(width: 26).foregroundStyle(available ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(task.title).font(.headline)
                    if task.requiresAdministrator { PocketStatusBadge(text: "Yönetici", systemImage: "lock", tone: .warning) }
                    if task.recommended { PocketStatusBadge(text: "Önerilen", tone: .accent) }
                    if case .unavailable = task.support { PocketStatusBadge(text: "Kullanılamıyor", systemImage: "minus.circle", tone: .neutral) }
                }
                Text(task.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let caution = task.caution {
                    Label(caution, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .unavailable(let reason) = task.support {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                statusLine
            }
            Spacer(minLength: PocketSpacing.m)
            Button("Çalıştır", action: run)
                .buttonStyle(.bordered)
                .disabled(busy || !available)
                .help(task.steps.map(\.commandLine).joined(separator: "\n"))
        }
        .padding(.vertical, PocketSpacing.s)
        .contentShape(Rectangle())
        .onTapGesture { if !busy { toggle() } }
        // The row toggles selection by click; VoiceOver and Full Keyboard Access need the same action.
        .accessibilityAction(named: Text("Seçimi değiştir")) { if !busy { toggle() } }
    }

    @ViewBuilder private var statusLine: some View {
        switch progress {
        case .waiting?:
            Label("Sırada", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        case .running?:
            HStack(spacing: PocketSpacing.xs) {
                ProgressView().controlSize(.mini)
                Text(task.requiresAdministrator ? "Yönetici onayı bekleniyor / çalışıyor…" : "Çalışıyor…")
            }
            .font(.caption).foregroundStyle(.secondary)
        case .finished(let outcome)?:
            outcomeLabel(outcome)
        case nil:
            if let lastRun {
                Label(String(localized: "Son çalıştırma: \(lastRun.date.formatted(.relative(presentation: .named)))"),
                      systemImage: lastRun.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func outcomeLabel(_ outcome: MaintenanceOutcome) -> some View {
        switch outcome {
        case let .ran(seconds, note):
            Label(String(localized: "Tamamlandı · \(seconds.formatted(.number.precision(.fractionLength(1)))) sn") + (note.map { " · \($0)" } ?? ""),
                  systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(PocketTone.success.color)
        case .skipped(let reason):
            Label(String(localized: "Atlandı: \(reason)"), systemImage: "arrow.uturn.right.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(String(localized: "Başarısız: \(message)"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(PocketTone.warning.color).textSelection(.enabled)
        }
    }
}
