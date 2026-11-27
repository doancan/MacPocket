import AppKit
import Darwin
import MacPocketCore
import SwiftUI

private enum ProcessScope: String, CaseIterable, Identifiable {
    case all = "Tümü", app = "Uygulamalar", background = "Arka plan", system = "Sistem"
    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .all: "Tümü"
        case .app: "Uygulamalar"
        case .background: "Arka plan"
        case .system: "Sistem"
        }
    }
}

struct TaskManagerView: View {
    var model: PocketModel
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var scope = ProcessScope.all
    @State private var selectedPID: Int32?
    @State private var selectedIdentity: ProcessIdentity?
    @State private var sortOrder = [KeyPathComparator(\ProcessEntry.cpuPercent, order: .reverse)]
    @State private var pendingEntry: ProcessEntry?
    @State private var pendingForce = false
    @State private var confirmTermination = false
    @AppStorage("manager.showUser") private var showUser = true
    @AppStorage("manager.showThreads") private var showThreads = true

    /// Filters and sorts the full process list. Expensive (~700 entries), so `body` evaluates it once
    /// and passes the result down instead of reading it from several places.
    private func filteredProcesses() -> [ProcessEntry] {
        let currentUser = getuid()
        return model.processes.filter { (entry: ProcessEntry) in
            let matches = search.isEmpty || "\(entry.name) \(entry.pid) \(entry.user)".localizedCaseInsensitiveContains(search)
            guard matches else { return false }
            let application = model.appPIDs.contains(entry.pid)
            let system = entry.identity.effectiveUserID != currentUser
            switch scope {
            case .all: return true
            case .app: return application
            case .system: return system
            case .background: return !application && !system
            }
        }.sorted(using: sortOrder)
    }

    var body: some View {
        let visible = filteredProcesses()
        let selected = selectedIdentity.flatMap { identity in visible.first { $0.identity == identity } }

        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Görev Yöneticisi",
                              subtitle: "Uygulamalar, arka plan işlemleri ve sistem süreçleri.",
                              icon: "list.bullet.rectangle") {
                PocketStatusBadge(text: model.paused ? "Duraklatıldı" : "Canlı · \(Int(model.refreshSeconds)) sn",
                                  systemImage: model.paused ? "pause.circle" : "waveform.path.ecg",
                                  tone: model.paused ? .warning : .success)
                    .help(model.paused ? "Canlı ölçüm duraklatıldı." : "Süreç listesi her yenileme aralığında güncellenir.")
            }
            ResourceStrip(model: model)
            controls
            HStack(spacing: 0) {
                processTable(visible, selected: selected)
                Divider()
                inspector(selected)
                    .frame(width: 260)
            }
            .pocketCard(padding: 0, radius: PocketRadius.medium)
            footer(visibleCount: visible.count)
            if let status = model.signalStatus {
                PocketMessage(status, tone: .accent)
            }
        }
        .pocketPage()
        .task { if !model.paused { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onChange(of: selectedPID) { _, pid in
            selectedIdentity = pid.flatMap { pid in visible.first { $0.pid == pid }?.identity }
        }
        .onChange(of: search) { _, _ in validateSelection(in: visible) }
        .onChange(of: scope) { _, _ in validateSelection(in: visible) }
        .onChange(of: model.lastUpdate) { _, _ in validateSelection(in: visible) }
        .alert(pendingForce ? "Süreç zorla sonlandırılsın mı?" : "Süreç sonlandırılsın mı?", isPresented: $confirmTermination) {
            Button("Vazgeç", role: .cancel) { pendingEntry = nil }
            Button(pendingForce ? "Zorla Sonlandır" : "Sonlandır", role: .destructive) {
                if let entry = pendingEntry {
                    let force = pendingForce
                    Task { await model.terminate(entry, force: force) }
                }
                pendingEntry = nil
            }
        } message: {
            if let entry = pendingEntry {
                let note: LocalizedStringKey = pendingForce ? "Kaydedilmemiş değişiklikler kaybolabilir." : "Normal sonlandırma isteği gönderilecek."
                Text("\(entry.name) · PID \(String(entry.pid))\n\(Text(note))")
            }
        }
    }

    // MARK: - Sections

    private var controls: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketSearchField("Ad, PID veya kullanıcı ara…", text: $search, focus: $searchFocused)
                .frame(maxWidth: 260)
                .accessibilityLabel("Süreç ara")
            GlassTabBar(tabs: ProcessScope.allCases.map { GlassTab(id: $0, title: $0.localizedTitle) }, selection: $scope)
            .accessibilityLabel("Kapsam")
            .frame(maxWidth: 340)
            .help("Süreçleri türüne göre filtrele")
            Spacer(minLength: PocketSpacing.s)
            Menu {
                Toggle("Kullanıcı", isOn: $showUser)
                Toggle("İş parçacığı", isOn: $showThreads)
            } label: {
                Label("Sütunlar", systemImage: "rectangle.split.3x1")
            }
            .fixedSize()
            .help("Tabloda gösterilecek isteğe bağlı sütunlar")
        }
    }

    private func processTable(_ visible: [ProcessEntry], selected: ProcessEntry?) -> some View {
        ProcessNativeTable(entries: visible, selection: $selectedPID,
                           showUser: showUser, showThreads: showThreads) { key, ascending in
            let order: SortOrder = ascending ? .forward : .reverse
            switch key {
            case "name": sortOrder = [KeyPathComparator(\ProcessEntry.name, order: order)]
            case "pid": sortOrder = [KeyPathComparator(\ProcessEntry.pid, order: order)]
            case "user": sortOrder = [KeyPathComparator(\ProcessEntry.user, order: order)]
            case "memory": sortOrder = [KeyPathComparator(\ProcessEntry.residentBytes, order: order)]
            case "state": sortOrder = [KeyPathComparator(\ProcessEntry.state, order: order)]
            default: sortOrder = [KeyPathComparator(\ProcessEntry.cpuPercent, order: order)]
            }
        }
        .contextMenu {
            if let entry = selected {
                Button("Sonlandır") { requestTermination(entry, force: false) }.disabled(!canSignal(entry))
                Button("Zorla Sonlandır", role: .destructive) { requestTermination(entry, force: true) }.disabled(!canSignal(entry))
            }
        }
        .overlay { tableOverlay(isEmpty: visible.isEmpty) }
    }

    @ViewBuilder
    private func tableOverlay(isEmpty: Bool) -> some View {
        if model.processes.isEmpty {
            if let error = model.error {
                PocketMessage(error, error: true).padding(PocketSpacing.l)
            } else if model.paused {
                ContentUnavailableView("Ölçüm duraklatıldı", systemImage: "pause.circle",
                                       description: Text("Süreçleri görmek için canlı ölçümü sürdür."))
            } else {
                ProgressView("Süreçler okunuyor…").controlSize(.small)
            }
        } else if isEmpty {
            if search.isEmpty {
                ContentUnavailableView("Bu kapsamda süreç yok", systemImage: "list.bullet.rectangle",
                                       description: Text("Farklı bir kapsam seç."))
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private func footer(visibleCount: Int) -> some View {
        HStack(spacing: PocketSpacing.s) {
            Text("\(visibleCount) gösterilen · \(model.processes.count) okunabilen · \(model.unreadableCount) erişilemeyen/çıkmış")
            Spacer(minLength: PocketSpacing.s)
            Label("CPU: tek çekirdeğe göre · Bellek: RSS", systemImage: "info.circle")
                .help("CPU yüzdesi tek mantıksal çekirdeğe göredir; çok iş parçacıklı süreçler %100'ü aşabilir. RSS paylaşılan sayfaları içerebilir, süreçlerin toplamı sistemin kullanılan belleği değildir.")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    // MARK: - Inspector

    @ViewBuilder
    private func inspector(_ selected: ProcessEntry?) -> some View {
        if let entry = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.m) {
                    inspectorHeader(entry)
                    Grid(alignment: .leading, horizontalSpacing: PocketSpacing.m, verticalSpacing: PocketSpacing.s) {
                        detail("Kullanıcı", entry.user)
                        detail("Durum", pocketProcessStateTitle(entry.state))
                        detail("Üst süreç", String(entry.parentPID))
                        detail("CPU", entry.cpuSampleAvailable ? pocketProcessCPU(entry.cpuPercent) : String(localized: "Örnek bekleniyor"))
                        detail("Bellek · RSS", entry.memorySampleAvailable ? pocketBytes(entry.residentBytes) : String(localized: "Okunamıyor"))
                        detail("İş parçacığı", entry.threadCount.map { String($0) } ?? "—")
                        detail("Başlangıç", Date(timeIntervalSince1970: Double(entry.identity.startSeconds))
                            .formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.callout)
                    .monospacedDigit()
                    Text(verbatim: entry.command.isEmpty ? String(localized: "Çalıştırılabilir dosya yolu okunamıyor") : entry.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(PocketSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PocketTheme.group, in: RoundedRectangle(cornerRadius: PocketRadius.small, style: .continuous))
                    Divider()
                    actions(entry)
                }
                .padding(PocketSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Süreç seçilmedi", systemImage: "cursorarrow.click",
                                   description: Text("Ayrıntılar ve işlemler için listeden bir süreç seç."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inspectorHeader(_ entry: ProcessEntry) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            processIcon(entry)
            Text(entry.name)
                .font(.headline)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack(spacing: PocketSpacing.s) {
                Text("PID \(entry.pid)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !entry.canTerminate {
                    PocketStatusBadge(text: "Korunan süreç", systemImage: "lock.shield", tone: .warning)
                        .help("macOS oturumu için kritik, sisteme veya başka bir kullanıcıya ait süreçler MacPocket'ten sonlandırılamaz.")
                }
            }
        }
    }

    @ViewBuilder
    private func processIcon(_ entry: ProcessEntry) -> some View {
        if model.appPIDs.contains(entry.pid),
           let url = NSRunningApplication(processIdentifier: entry.pid)?.bundleURL {
            PocketAppIcon(url: url, size: 40)
        } else {
            Image(systemName: entry.canTerminate ? "gearshape.2" : "lock.shield")
                .font(.title2)
                .foregroundStyle(entry.canTerminate ? PocketTheme.accent : .secondary)
                .frame(width: 40, height: 40)
                .background(PocketTheme.group, in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func actions(_ entry: ProcessEntry) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Button { requestTermination(entry, force: false) } label: {
                Label("Sonlandır", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!canSignal(entry))
            .help("Normal sonlandırma isteği (SIGTERM) gönderir")
            Button(role: .destructive) { requestTermination(entry, force: true) } label: {
                Label("Zorla Sonlandır", systemImage: "xmark.octagon").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pocketPrimary)
            .tint(.red)
            .controlSize(.large)
            .disabled(!canSignal(entry))
            .help("Süreci hemen durdurur (SIGKILL); kaydedilmemiş değişiklikler kaybolabilir")
            Text(entry.canTerminate
                 ? "İşlem, sürecin kimliği yeniden doğrulandıktan sonra uygulanır."
                 : "Bu süreç korunuyor veya sonlandırma erişimi bulunmuyor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func canSignal(_ entry: ProcessEntry) -> Bool { entry.canTerminate && model.terminatingPID == nil }

    private func requestTermination(_ entry: ProcessEntry, force: Bool) {
        pendingEntry = entry
        pendingForce = force
        confirmTermination = true
    }

    private func validateSelection(in visible: [ProcessEntry]) {
        guard let selectedIdentity else { return }
        if !visible.contains(where: { $0.identity == selectedIdentity }) {
            selectedPID = nil
            self.selectedIdentity = nil
        }
    }
}
