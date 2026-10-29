import AppKit
import Darwin
import MacPocketCore
import SwiftUI

private enum ProcessScope: String, CaseIterable, Identifiable {
    case all = "Tümü", app = "Uygulamalar", background = "Arka plan", system = "Sistem"
    var id: String { rawValue }
}

struct TaskManagerView: View {
    @ObservedObject var model: PocketModel
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

    private var visibleProcesses: [ProcessEntry] {
        model.processes.filter { (entry: ProcessEntry) in
            let matches = search.isEmpty || "\(entry.name) \(entry.pid) \(entry.user)".localizedCaseInsensitiveContains(search)
            let application = model.appPIDs.contains(entry.pid)
            let system = entry.identity.effectiveUserID != getuid()
            let category = scope == .all || (scope == .app && application)
                || (scope == .system && system)
                || (scope == .background && !application && !system)
            return matches && category
        }.sorted(using: sortOrder)
    }

    private var selectedEntry: ProcessEntry? {
        guard let selectedIdentity else { return nil }
        return visibleProcesses.first { $0.identity == selectedIdentity }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Görev Yöneticisi").font(.system(size: 23, weight: .semibold))
                    Text("Uygulamalar, arka plan işlemleri ve sistem süreçleri.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.paused ? "Duraklatıldı" : "Canlı · \(Int(model.refreshSeconds)) sn",
                      systemImage: model.paused ? "pause.circle" : "waveform.path.ecg")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ResourceStrip(model: model)
            HStack {
                Label("Süreçler", systemImage: "list.bullet").foregroundStyle(PocketTheme.accent)
                Text("Canlı interval ölçümü").foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 11)).padding(.vertical, 6).overlay(alignment: .bottom) { Divider() }
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Ad, PID veya kullanıcı ara…", text: $search).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Süreç ara")
                }.font(.system(size: 11)).padding(8).frame(width: 250)
                    .background(PocketTheme.sidebar).clipShape(RoundedRectangle(cornerRadius: 5))
                Picker("Kapsam", selection: $scope) {
                    ForEach(ProcessScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 330)
                Spacer()
                Menu {
                    Toggle("Kullanıcı", isOn: $showUser)
                    Toggle("İş parçacığı", isOn: $showThreads)
                } label: { Label("Sütunlar", systemImage: "rectangle.split.3x1") }
                    .frame(width: 108)
            }
            HStack(spacing: 0) {
                ProcessNativeTable(entries: visibleProcesses, selection: $selectedPID,
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
                    if let entry = selectedEntry {
                        Button("Sonlandır") { requestTermination(entry, force: false) }.disabled(!canSignal(entry))
                        Button("Zorla Sonlandır", role: .destructive) { requestTermination(entry, force: true) }.disabled(!canSignal(entry))
                    }
                }
                Divider()
                inspector.frame(width: 248)
            }
            .background(PocketTheme.panel).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(PocketTheme.line) }
            HStack {
                Text("\(visibleProcesses.count) gösterilen · \(model.processes.count) okunabilen · \(model.unreadableCount) erişilemeyen/çıkmış")
                Spacer()
                Text("CPU: tek çekirdeğe göre · Bellek: RSS")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            if let status = model.signalStatus {
                Text(status).font(.system(size: 11)).foregroundStyle(PocketTheme.accent).textSelection(.enabled)
            }
        }
        .padding(22)
        .task { if !model.paused { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onChange(of: selectedPID) { _, pid in
            selectedIdentity = visibleProcesses.first { $0.pid == pid }?.identity
        }
        .onChange(of: search) { _, _ in validateSelection() }
        .onChange(of: scope) { _, _ in validateSelection() }
        .onChange(of: model.lastUpdate) { _, _ in validateSelection() }
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
                Text("\(entry.name) · PID \(entry.pid)\n\(pendingForce ? "Kaydedilmemiş değişiklikler kaybolabilir." : "Normal sonlandırma isteği gönderilecek.")")
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("SÜREÇ AYRINTILARI").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if let entry = selectedEntry {
                    Image(systemName: "app.window").font(.system(size: 27)).foregroundStyle(PocketTheme.accent).padding(.top, 8)
                    Text(entry.name).font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                    Text("PID \(entry.pid)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        detail("Kullanıcı", entry.user)
                        detail("Durum", entry.state)
                        detail("Üst süreç", String(entry.parentPID))
                        detail("CPU", entry.cpuSampleAvailable ? String(format: "%.1f%%", entry.cpuPercent) : "Örnek bekleniyor")
                        detail("Bellek · RSS", entry.memorySampleAvailable ? pocketBytes(entry.residentBytes) : "Okunamıyor")
                        detail("İş parçacığı", entry.threadCount.map { String($0) } ?? "—")
                    }.font(.system(size: 10)).monospacedDigit()
                    Text("Başlangıç: \(Date(timeIntervalSince1970: Double(entry.identity.startSeconds)).formatted(date: .abbreviated, time: .standard))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(entry.command.isEmpty ? "Executable yolu okunamıyor" : entry.command)
                        .font(.system(size: 9, design: .monospaced)).textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(PocketTheme.sidebar)
                    Button { requestTermination(entry, force: false) } label: {
                        Label("Sonlandır", systemImage: "stop").frame(maxWidth: .infinity)
                    }.disabled(!canSignal(entry))
                    Button(role: .destructive) { requestTermination(entry, force: true) } label: {
                        Label("Zorla Sonlandır", systemImage: "xmark.octagon").frame(maxWidth: .infinity)
                    }.disabled(!canSignal(entry))
                    Text(entry.canTerminate ? "İşlem, seçtiğin sürecin kimliği yeniden doğrulandıktan sonra uygulanır." : "Bu süreç korunuyor veya sonlandırma erişimi bulunmuyor.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider()
                    Text("RSS paylaşılan sayfaları içerebilir. Süreçlerin toplamı sistemin kullanılan belleği değildir.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Ayrıntıları görmek ve işlem yapmak için listeden bir süreç seç.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        GridRow { Text(title).foregroundStyle(.secondary); Text(value).frame(maxWidth: .infinity, alignment: .trailing) }
    }
    private func canSignal(_ entry: ProcessEntry) -> Bool { entry.canTerminate && model.terminatingPID == nil }
    private func requestTermination(_ entry: ProcessEntry, force: Bool) {
        pendingEntry = entry
        pendingForce = force
        confirmTermination = true
    }
    private func validateSelection() {
        guard let selectedIdentity else { return }
        if !visibleProcesses.contains(where: { $0.identity == selectedIdentity }) {
            selectedPID = nil
            self.selectedIdentity = nil
        }
    }
}
