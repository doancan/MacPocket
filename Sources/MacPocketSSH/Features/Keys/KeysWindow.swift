import SSHConfigKit
import SwiftUI

struct KeysWindow: View {
    let app: AppModel
    @State private var sheet: KeySheet?
    @State private var trashing: KeyRow?

    enum KeySheet: Identifiable {
        case new, addToAgent(KeyRow), changePassphrase(KeyRow), upload(KeyRow)
        var id: String {
            switch self {
            case .new: "new"
            case .addToAgent(let row): "agent-" + row.id
            case .changePassphrase(let row): "pass-" + row.id
            case .upload(let row): "upload-" + row.id
            }
        }
    }

    private var keys: KeysModel { app.keys }

    var body: some View {
        @Bindable var keys = app.keys
        Table(keys.rows, selection: $keys.selection) {
            TableColumn(String(localized: "SSH.keys.column.name", defaultValue: "Ad")) { row in
                HStack(spacing: 4) {
                    if row.key.unreadable {
                        Image(systemName: "lock.slash").foregroundStyle(.orange)
                            .help(String(localized: "SSH.keys.unreadable", defaultValue: "Özel anahtar okunamıyor (izinlerini kontrol edin)"))
                            .accessibilityLabel(String(localized: "SSH.keys.unreadable", defaultValue: "Özel anahtar okunamıyor (izinlerini kontrol edin)"))
                    } else if !row.key.hasPrivateKey {
                        Image(systemName: "key.slash").foregroundStyle(.secondary)
                            .help(String(localized: "SSH.keys.noPrivateKey", defaultValue: "Özel anahtar yok"))
                            .accessibilityLabel(String(localized: "SSH.keys.noPrivateKey", defaultValue: "Özel anahtar yok"))
                    }
                    Text(verbatim: row.displayPath).lineLimit(1).help(row.displayPath)
                }
            }
            TableColumn(String(localized: "SSH.keys.column.type", defaultValue: "Tip")) { row in
                let bits = row.key.bits.map(String.init) ?? ""
                Text(verbatim: [row.key.typeLabel ?? row.key.publicKey?.type ?? "", bits].filter { !$0.isEmpty }.joined(separator: " "))
            }
            .width(min: 70, ideal: 100)
            TableColumn(String(localized: "SSH.keys.column.fingerprint", defaultValue: "Parmak İzi (SHA256)")) { row in
                Text(verbatim: row.key.publicKey?.fingerprint ?? "").font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
            }
            .width(min: 180, ideal: 320)
            TableColumn(String(localized: "SSH.keys.column.comment", defaultValue: "Yorum")) { row in Text(verbatim: row.key.publicKey?.comment ?? "") }
            TableColumn(String(localized: "SSH.keys.column.passphrase", defaultValue: "Parola")) { row in passphraseCell(row) }
                .width(min: 60, ideal: 80)
            TableColumn(String(localized: "SSH.keys.column.agent", defaultValue: "Agent")) { row in agentCell(row) }
                .width(min: 60, ideal: 80)
            TableColumn(String(localized: "SSH.keys.column.usedBy", defaultValue: "Kullanan")) { row in
                Text(verbatim: row.usedBy.joined(separator: ", ")).lineLimit(1).help(row.usedBy.joined(separator: "\n"))
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let row = keys.rows.first(where: { $0.id == id }) { actions(for: row) }
        }
        .overlay {
            if keys.rows.isEmpty && !keys.isRefreshing {
                ContentUnavailableView(String(localized: "SSH.keys.empty", defaultValue: "Anahtar bulunamadı"), systemImage: "key")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .new } label: { Label(String(localized: "SSH.keys.new", defaultValue: "Yeni Anahtar…"), systemImage: "plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await keys.refresh() } } label: {
                    Label(String(localized: "SSH.keys.refresh", defaultValue: "Yenile"), systemImage: "arrow.clockwise")
                }
                .disabled(keys.isRefreshing)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let row = selectedRow { actions(for: row) }
                } label: {
                    Label(String(localized: "SSH.keys.actions", defaultValue: "İşlemler"), systemImage: "ellipsis.circle")
                }
                .disabled(selectedRow == nil)
            }
        }
        .onChange(of: keys.passphraseRequestedFor) {
            if let id = keys.passphraseRequestedFor, let row = keys.rows.first(where: { $0.id == id }) { sheet = .addToAgent(row) }
            keys.passphraseRequestedFor = nil
        }
        .onChange(of: keys.pendingNewKey, initial: true) {
            if keys.pendingNewKey { sheet = .new; keys.pendingNewKey = false }
        }
        .sheet(item: $sheet) { item in
            // A sheet closes only itself: an operation finishing late must not close a sheet opened after it.
            let close = { if sheet?.id == item.id { sheet = nil } }
            switch item {
            case .new: NewKeySheet(keys: keys, assignableAliases: app.assignableAliases, close: close)
            case .addToAgent(let row): AddToAgentSheet(keys: keys, row: row, close: close)
            case .changePassphrase(let row): ChangePassphraseSheet(keys: keys, row: row, close: close)
            case .upload(let row): UploadKeySheet(app: app, row: row, close: close)
            }
        }
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
            presenting: trashing
        ) { row in
            Button(String(localized: "SSH.keys.trash", defaultValue: "Çöp Kutusuna Taşı…"), role: .destructive) { Task { _ = await keys.trash(row) } }
        } message: { row in
            let hosts = row.usedBy.joined(separator: ", ")
            Text(row.usedBy.isEmpty ? String(localized: "SSH.keys.trash.message", defaultValue: "Özel anahtar ve .pub dosyası birlikte çöp kutusuna taşınır.")
                 : String(localized: "SSH.keys.trash.message", defaultValue: "Özel anahtar ve .pub dosyası birlikte çöp kutusuna taşınır.") + "\n\n" + String(localized: "SSH.keys.trash.inUse %@", defaultValue: "Bu anahtarı kullanan hostlar: \(hosts)"))
        }
        .alert(
            String(localized: "SSH.error.title", defaultValue: "Bir Sorun Oluştu"),
            isPresented: Binding(get: { sheet == nil && keys.errorMessage != nil }, set: { if !$0 { keys.errorMessage = nil } })
        ) {
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat")) { keys.errorMessage = nil }
        } message: {
            Text(verbatim: keys.errorMessage ?? "")
        }
        .alert(
            String(localized: "SSH.keys.notice.title", defaultValue: "Bilgi"),
            isPresented: Binding(get: { sheet == nil && keys.errorMessage == nil && keys.notice != nil },
                                 set: { if !$0 { keys.notice = nil; keys.noticeIsAutomationDenied = false } })
        ) {
            if keys.noticeIsAutomationDenied {
                Button(String(localized: "SSH.connect.automationDenied.open", defaultValue: "Gizlilik Ayarlarını Aç")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat"), role: .cancel) {}
        } message: {
            Text(verbatim: keys.notice ?? "")
        }
        .task { await keys.refresh() }
        .onChange(of: app.store.savedDocument) { Task { await keys.refresh() } }
        .onChange(of: app.store.fileURL) { Task { await keys.refresh() } }
        .onChange(of: ObjectIdentifier(app.store)) { Task { await keys.refresh() } }
        .frame(minWidth: 0, minHeight: 320)
    }

    private var trashTitle: String {
        guard let shownPath = trashing?.displayPath else { return "" }
        return String(localized: "SSH.keys.trash.which %@", defaultValue: "“\(shownPath)” çöp kutusuna taşınsın mı?")
    }

    private var selectedRow: KeyRow? {
        keys.rows.first { $0.id == keys.selection }
    }

    @ViewBuilder
    private func actions(for row: KeyRow) -> some View {
        Button(String(localized: "SSH.keys.copyPublic", defaultValue: "Public Key'i Kopyala")) { keys.copyPublicKey(row) }
            .disabled(row.key.publicURL == nil)
        Button(String(localized: "SSH.keys.addToAgent", defaultValue: "Agent'a Ekle…")) {
            if row.key.encryption == .unencrypted {
                Task { _ = await keys.addToAgent(row, passphrase: nil) }
            } else {
                sheet = .addToAgent(row)
            }
        }
        .disabled(!row.key.hasPrivateKey || row.key.unreadable)
        Button(String(localized: "SSH.keys.upload", defaultValue: "Sunucuya Yükle…")) { sheet = .upload(row) }
            .disabled(row.key.publicURL == nil || !row.key.hasPrivateKey)
            .help(row.key.publicURL == nil ? String(localized: "SSH.keys.upload.noPublicKey", defaultValue: "Bu anahtarın yüklenecek .pub dosyası yok.")
                  : row.key.hasPrivateKey ? "" : String(localized: "SSH.keys.upload.needsPrivateKey", defaultValue: "ssh-copy-id, .pub dosyasının yanında özel anahtarı ister."))
        Button(String(localized: "SSH.keys.changePassphrase", defaultValue: "Parolayı Değiştir…")) { sheet = .changePassphrase(row) }
            .disabled(!row.key.hasPrivateKey || row.key.unreadable)
        Divider()
        Button(String(localized: "SSH.keys.trash", defaultValue: "Çöp Kutusuna Taşı…"), role: .destructive) { trashing = row }
    }

    @ViewBuilder
    private func passphraseCell(_ row: KeyRow) -> some View {
        switch row.key.encryption {
        case .encrypted:
            Text(String(localized: "SSH.keys.passphrase.yes", defaultValue: "Var"))
        case .unencrypted:
            Label(String(localized: "SSH.keys.passphrase.no", defaultValue: "Yok"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(String(localized: "SSH.keys.passphrase.noHelp", defaultValue: "Bu özel anahtarın parolası yok. Dosyayı kopyalayan herkes kullanabilir."))
        case .unknown where row.key.unreadable:
            Image(systemName: "lock.slash").foregroundStyle(.orange)
                .help(String(localized: "SSH.keys.unreadable", defaultValue: "Özel anahtar okunamıyor (izinlerini kontrol edin)"))
                .accessibilityLabel(String(localized: "SSH.keys.unreadable", defaultValue: "Özel anahtar okunamıyor (izinlerini kontrol edin)"))
        case .unknown:
            Text(verbatim: "—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func agentCell(_ row: KeyRow) -> some View {
        switch row.inAgent {
        case .some(true):
            Label(String(localized: "SSH.keys.agent.loaded", defaultValue: "Yüklü"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(false):
            Text(verbatim: "—").foregroundStyle(.secondary)
        case .none:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .help(String(localized: "SSH.keys.agent.unknown", defaultValue: "Agent'a erişilemiyor"))
                .accessibilityLabel(String(localized: "SSH.keys.agent.unknown", defaultValue: "Agent'a erişilemiyor"))
        }
    }
}
