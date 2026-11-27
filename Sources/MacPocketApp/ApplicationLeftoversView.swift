import AppKit
import MacPocketCore
import SwiftUI

@MainActor
final class ApplicationLeftoversModel: ObservableObject {
    @Published private(set) var rows: [ApplicationLeftover] = []
    @Published var selection = Set<String>()
    @Published private(set) var busy = false
    @Published private(set) var scanned = false
    @Published private(set) var progress = ""
    @Published var message: String?
    @Published var failure: String?
    @Published var search = "" { didSet { if search != oldValue { selection = [] } } }
    private var operation: Task<Void, Never>?

    var filtered: [ApplicationLeftover] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.bundleID.localizedCaseInsensitiveContains(query) || $0.request.url.path.localizedCaseInsensitiveContains(query) }
    }
    var selectedRows: [ApplicationLeftover] { filtered.filter { selection.contains($0.id) } }

    func scan() {
        guard !busy else { return }
        busy = true
        selection = []
        message = nil
        failure = nil
        progress = String(localized: "Kurulu uygulamalar ve Library konumları inceleniyor…")
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                let installed = try await ApplicationInventory().scan()
                try Task.checkCancellation()
                // An empty inventory would make every item look orphaned; refuse to build a list.
                guard !installed.isEmpty else {
                    rows = []
                    scanned = false
                    failure = String(localized: "Uygulama envanteri okunamadı; güvenlik için kalıntı listesi oluşturulmadı.")
                    return
                }
                let candidates = try await ApplicationLeftoverScanner().scan(installedIDs: Set(installed.map(\.bundleID)))
                rows = candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) == nil }
                scanned = true
                let shared = rows.filter(\.sharedVendor).count
                message = shared > 0
                    ? String(localized: "\(rows.count) aday bulundu. \(shared) öğenin üreticisine ait başka bir uygulama kurulu.")
                    : String(localized: "\(rows.count) aday bulundu.")
            } catch is CancellationError {
                message = String(localized: "Tarama iptal edildi.")
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func cancel() { operation?.cancel() }

    func trash() {
        guard !busy else { return }
        let selected = selectedRows
        guard !selected.isEmpty else { return }
        busy = true
        failure = nil
        message = nil
        progress = String(localized: "Envanter yeniden doğrulanıyor…")
        operation = Task {
            defer { busy = false; operation = nil }
            let installedIDs: Set<String>
            do {
                let inventory = try await ApplicationInventory().scan()
                try Task.checkCancellation()
                guard !inventory.isEmpty else {
                    failure = String(localized: "Uygulama envanteri okunamadı; güvenlik için hiçbir öğe taşınmadı.")
                    return
                }
                installedIDs = Set(inventory.map(\.bundleID))
            } catch {
                if error is CancellationError { message = String(localized: "İşlem iptal edildi.") } else { failure = error.localizedDescription }
                return
            }
            let stillUnregistered = selected.filter { candidate in
                !installedIDs.contains(where: { candidate.bundleID == $0 || candidate.bundleID.hasPrefix($0 + ".") })
                    && NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) == nil
            }
            let mode = RemovalModePreference.load()
            progress = mode.inProgress(stillUnregistered.count)
            let results = await FileTrashService().remove(stillUnregistered.map(\.request), mode: mode)
            let moved = Set(results.filter(\.succeeded).map(\.id))
            rows.removeAll { moved.contains($0.id) }
            selection = []
            let skipped = selected.count - stillUnregistered.count
            message = skipped > 0
                ? mode.completed(moved.count) + " " + String(localized: "\(skipped) öğe artık kurulu bir uygulamayla eşleştiği için atlandı.")
                : mode.completed(moved.count)
            let errors = results.compactMap(\.error)
            failure = errors.isEmpty ? nil : errors.prefix(3).joined(separator: "\n")
        }
    }
}

/// The Uygulama Kalıntıları tab of the Applications page; its scan actions live in the page heading.
struct ApplicationLeftoversSection: View {
    @ObservedObject var model: ApplicationLeftoversModel
    @State private var confirm = false
    @State private var showInfo = false
    @AppStorage(RemovalModePreference.storageKey) private var removalMode: RemovalMode = .deletePermanently
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            HStack(spacing: PocketSpacing.s) {
                Text("Kurulu veya kayıtlı bir uygulamayla eşleşmeyen bundle kimliği adayları. Aday olması gereksiz olduğu anlamına gelmez; taşınmadan önce incele.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Tarama kapsamı hakkında")
                    .help("Tarama kapsamı ve güvenlik notları")
                    .popover(isPresented: $showInfo, arrowEdge: .bottom) { infoPopover }
                Spacer(minLength: 0)
            }
            FullDiskAccessBanner(consequence: "Korunan klasörlerdeki kalıntılar taramaya girmez.")
            if model.busy { PocketProgressRow(message: model.progress) }
            if let failure = model.failure { PocketMessage(failure, tone: .critical) }
            if let message = model.message { PocketMessage(message, tone: .success) }
            if model.scanned {
                results
            } else if !model.busy {
                ContentUnavailableView {
                    Label("Kalıntıları tara", systemImage: "square.dashed")
                } description: {
                    Text("Tarama dosyaları değiştirmez. Taşınacak öğeleri sonuçlardan sen seçersin.")
                } actions: {
                    Button("Tara") { model.scan() }.buttonStyle(.pocketPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketFind)) { _ in searchFocused = true }
        .onDisappear { model.cancel() }
        .alert(removalMode == .deletePermanently ? "Seçili adaylar kalıcı olarak silinsin mi?" : "Seçili adaylar Çöp’e taşınsın mı?", isPresented: $confirm) {
            Button("Vazgeç", role: .cancel) {}
            Button(removalMode == .deletePermanently ? "Kalıcı Olarak Sil" : "Çöp’e Taşı", role: .destructive) { model.trash() }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        let selected = model.selectedRows
        let shared = selected.filter(\.sharedVendor).count
        if shared > 0 {
            return String(localized: "Seçilen \(selected.count) öğe tercih veya kullanıcı verisi içerebilir. Uygulaması başka yerdeyse bu verilere ihtiyaç duyabilir. \(shared) öğenin üreticisine ait başka bir uygulama kurulu; bu öğeler hâlâ kullanılıyor olabilir. \(recoveryNote)")
        }
        return String(localized: "Seçilen \(selected.count) öğe tercih veya kullanıcı verisi içerebilir. Uygulaması başka yerdeyse bu verilere ihtiyaç duyabilir. \(recoveryNote)")
    }

    private var recoveryNote: String {
        removalMode == .deletePermanently ? String(localized: "Kalıcı silme geri alınamaz.") : String(localized: "Gerekirse Finder’daki Çöp’ten geri alabilirsin.")
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Text("Tarama kapsamı").font(.headline)
            Label("Taşınmış veya başka diskteki uygulamaların verileri de aday olarak görünebilir.", systemImage: "externaldrive.badge.questionmark")
            Label("“Üretici uygulaması kurulu” işaretli öğeler aynı üreticinin başka bir uygulaması tarafından kullanılıyor olabilir.", systemImage: "building.2")
            Label("Kullanıcı Library içindeki yedi konumun her birinde en fazla 10.000 doğrudan öğe incelenir; erişilemeyen klasörler atlanır.", systemImage: "folder.badge.questionmark")
            Label("Silmeden önce envanter yeniden doğrulanır. Çöp’e taşıma seçiliyse öğeler Çöp’ten geri alınabilir.", systemImage: "trash")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 340)
        .padding(PocketSpacing.l)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketSearchField("Bundle kimliği veya konum ara…", text: $model.search, focus: $searchFocused)
                    .frame(maxWidth: 360)
                    .accessibilityLabel("Kalıntılarda ara")
                Spacer(minLength: PocketSpacing.s)
                Text("\(model.filtered.count) aday").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Table(model.filtered, selection: $model.selection) {
                TableColumn("Bundle kimliği") { item in
                    Text(item.bundleID).lineLimit(1).help(item.bundleID)
                }
                .width(min: 200, ideal: 300)
                TableColumn("Tür") { item in
                    Text(item.category).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 130)
                TableColumn("Durum") { item in
                    if item.sharedVendor {
                        PocketStatusBadge(text: "Üretici uygulaması kurulu" as LocalizedStringKey, systemImage: "building.2", tone: .warning)
                            .help("Aynı üreticinin başka bir uygulaması kurulu; bu öğe hâlâ kullanılıyor olabilir.")
                    } else {
                        Text("Eşleşme yok").foregroundStyle(.secondary)
                    }
                }
                .width(min: 120, ideal: 190)
                TableColumn("Konum") { item in
                    Text(item.request.url.path).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(item.request.url.path)
                }
            }
            .tableStyle(.inset)
            .disabled(model.busy)
            .overlay {
                if model.filtered.isEmpty && !model.busy {
                    if model.search.isEmpty {
                        ContentUnavailableView("Kalıntı adayı bulunamadı", systemImage: "checkmark.seal",
                                               description: Text("İncelenen konumlarda kurulu uygulamalarla eşleşmeyen öğe yok."))
                    } else {
                        ContentUnavailableView.search(text: model.search)
                    }
                }
            }
            HStack(spacing: PocketSpacing.s) {
                Text("\(model.selectedRows.count) seçili").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: PocketSpacing.s)
                Button("Finder’da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting(model.selectedRows.map(\.request.url))
                }
                .disabled(model.selection.isEmpty)
                .help("Seçili öğeleri Finder’da göster")
                RemovalModePicker().disabled(model.busy)
                Button(removalMode.actionTitle, role: .destructive) { confirm = true }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selectedRows.isEmpty || model.busy)
                    .help("Seçili adayları kaldır (⌘⌫)")
            }
        }
    }
}

/// Scan and cancel buttons for the leftovers tab, shown in the Applications page heading.
struct ApplicationLeftoversActions: View {
    @ObservedObject var model: ApplicationLeftoversModel

    var body: some View {
        if model.busy {
            Button("İptal Et", role: .cancel) { model.cancel() }
                .keyboardShortcut(.cancelAction)
                .help("Süren işlemi durdur")
        } else {
            Button("Tara") { model.scan() }
                .buttonStyle(.pocketPrimary)
                .help(model.scanned ? "Yeniden tara" : "Library konumlarını tara")
        }
    }
}
