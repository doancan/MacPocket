import MacPocketCore
import SwiftUI

@MainActor
final class MaintenanceModel: ObservableObject {
    let tasks = MaintenanceCatalog.tasks()
    @Published var selected: Set<MaintenanceTaskID>
    @Published private(set) var results: [MaintenanceResult] = []
    @Published private(set) var running = false
    private var runTask: Task<Void, Never>?

    init() { selected = Set(tasks.filter { $0.support == .ready }.map(\.id)) }

    var runnable: [MaintenanceTask] { tasks.filter { selected.contains($0.id) } }

    func toggle(_ task: MaintenanceTask) {
        guard task.support == .ready else { return }
        if selected.contains(task.id) { selected.remove(task.id) } else { selected.insert(task.id) }
    }

    func run() {
        guard !running else { return }
        let chosen = runnable
        guard !chosen.isEmpty else { return }
        running = true
        results = []
        runTask = Task { [weak self] in
            let results = await MaintenanceRunner.run(chosen)
            self?.results = results
            self?.running = false
        }
    }

    func cancel() { runTask?.cancel() }
}

/// Tools → Bakım: small fixes for macOS services, with an honest account of what ran and what was skipped.
struct MaintenanceView: View {
    @StateObject private var model = MaintenanceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Bakım",
                              subtitle: "macOS’un önbellek ve hizmetleri için küçük düzeltmeleri tek seferde çalıştır; neyin çalıştığını ve neyin neden atlandığını gör.",
                              icon: "wrench.and.screwdriver")
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    VStack(spacing: 0) {
                        ForEach(model.tasks) { task in
                            TaskRow(task: task, selected: model.selected.contains(task.id), disabled: model.running) { model.toggle(task) }
                            if task.id != model.tasks.last?.id { Divider() }
                        }
                    }
                    .pocketCard()
                    HStack(spacing: PocketSpacing.m) {
                        if model.running {
                            Button("Durdur", role: .cancel) { model.cancel() }
                            PocketProgressRow(message: "Çalışıyor…")
                        } else {
                            Button { model.run() } label: {
                                Label("Çalıştır", systemImage: "play.fill").padding(.horizontal, PocketSpacing.s)
                            }
                            .buttonStyle(.pocketPrimary)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.runnable.isEmpty)
                        }
                    }
                    if !model.results.isEmpty { resultsCard }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Sonuç", icon: "checklist")
            ForEach(model.results) { result in
                HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.s) {
                    outcomeIcon(result.outcome)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.task.title).font(.subheadline.weight(.semibold))
                        Text(outcomeText(result.outcome)).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    @ViewBuilder
    private func outcomeIcon(_ outcome: MaintenanceOutcome) -> some View {
        switch outcome {
        case .ran: Image(systemName: "checkmark.circle.fill").foregroundStyle(PocketTone.success.color)
        case .skipped: Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PocketTone.warning.color)
        }
    }

    private func outcomeText(_ outcome: MaintenanceOutcome) -> String {
        switch outcome {
        case .ran(let seconds): String(localized: "Çalıştı · \(seconds.formatted(.number.precision(.fractionLength(1)))) sn")
        case .skipped(let reason): String(localized: "Atlandı: \(reason)")
        case .failed(let message): String(localized: "Başarısız: \(message)")
        }
    }
}

private struct TaskRow: View {
    let task: MaintenanceTask
    let selected: Bool
    let disabled: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PocketSpacing.m) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(disabled || task.support != .ready)
                .accessibilityLabel(Text(task.title))
            Image(systemName: task.symbol).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(task.title).font(.headline)
                    switch task.support {
                    case .ready: EmptyView()
                    case .needsAdministrator: PocketStatusBadge(text: "Yönetici gerektirir", systemImage: "lock", tone: .warning)
                    case .unavailable: PocketStatusBadge(text: "Kullanılamıyor", systemImage: "minus.circle", tone: .neutral)
                    }
                }
                Text(task.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if case .unavailable(let reason) = task.support {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PocketSpacing.s)
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { toggle() } }
    }
}
