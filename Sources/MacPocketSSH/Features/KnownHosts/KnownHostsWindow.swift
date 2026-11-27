import SSHConfigKit
import SwiftUI

struct KnownHostsWindow: View {
    @State private var model: KnownHostsModel
    @FocusState private var searchFocused: Bool

    init(app: AppModel) {
        _model = State(initialValue: KnownHostsModel(app: app))
    }

    var body: some View {
        // Computed once per render: the table and the empty overlay share it.
        let rows = model.rows
        let loadingFirstTime = model.isLoadingFirstTime
        return VStack(spacing: 0) {
            TextField(String(localized: "SSH.knownHosts.search.prompt", defaultValue: "Host ara ya da hash'li kayıtları bulmak için host adı yaz"), text: $model.searchText)
                .textFieldStyle(.bordered).textInputBorderShape(.roundedRectangle)
                .focused($searchFocused)
                .padding(10)
            if !loadingFirstTime, let message = Messages.knownHostsLoadText(for: model.app.knownHosts.loadState) {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary)
            }
            Table(rows, selection: $model.selection) {
                TableColumn(String(localized: "SSH.knownHosts.column.host", defaultValue: "Host")) { row in
                    HStack(spacing: 4) {
                        if row.isUnparsable {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(String(localized: "SSH.knownHosts.unparsable.help", defaultValue: "Bu satır anlaşılamadı. Olduğu gibi korunur."))
                                .accessibilityLabel(String(localized: "SSH.knownHosts.unparsable.help", defaultValue: "Bu satır anlaşılamadı. Olduğu gibi korunur."))
                        }
                        if row.isHashed { Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
                        Text(verbatim: row.hosts).lineLimit(1).textSelection(.enabled)
                    }
                }
                TableColumn(String(localized: "SSH.knownHosts.column.port", defaultValue: "Port")) { row in Text(verbatim: row.ports) }
                    .width(min: 50, ideal: 60)
                TableColumn(String(localized: "SSH.knownHosts.column.type", defaultValue: "Anahtar Tipi")) { row in Text(verbatim: row.keyType) }
                TableColumn(String(localized: "SSH.knownHosts.column.fingerprint", defaultValue: "Parmak İzi (SHA256)")) { row in
                    Text(verbatim: row.fingerprint).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                }
                .width(min: 200, ideal: 330)
                TableColumn(String(localized: "SSH.knownHosts.column.marker", defaultValue: "İşaret")) { row in Text(verbatim: row.marker) }
                    .width(min: 60, ideal: 110)
            }
            .overlay {
                if loadingFirstTime {
                    ProgressView()
                } else if rows.isEmpty {
                    ContentUnavailableView(String(localized: "SSH.knownHosts.empty", defaultValue: "Kayıt yok"), systemImage: "checkmark.shield")
                }
            }
            .onDeleteCommand { model.requestRemoveSelection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacPocket.find"))) { _ in searchFocused = true }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    model.requestRemoveSelection()
                } label: {
                    Label(String(localized: "SSH.knownHosts.delete", defaultValue: "Sil"), systemImage: "trash")
                }
                .disabled(!model.canRemoveSelection)
            }
        }
        .confirmationDialog(
            String(localized: "SSH.knownHosts.delete.confirm.title", defaultValue: "Seçili known_hosts kayıtları silinsin mi?"),
            isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.cancelRemoval() } }),
            presenting: model.pendingRemoval
        ) { _ in
            Button(String(localized: "SSH.knownHosts.delete", defaultValue: "Sil"), role: .destructive) { model.confirmRemoval() }
        } message: { rows in
            Text(verbatim: KnownHostsModel.summary(of: rows) + "\n\n" + String(localized: "SSH.knownHosts.delete.confirm.message", defaultValue: "Önce yedek alınır. Yedekler ekranından geri yükleyebilirsiniz."))
        }
        .alert(
            String(localized: "SSH.error.title", defaultValue: "Bir Sorun Oluştu"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat")) { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .frame(minWidth: 0, minHeight: 320)
    }
}
