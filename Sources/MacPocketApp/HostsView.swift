import MacPocketCore
import SwiftUI

@MainActor
final class HostsModel: ObservableObject {
    @Published private(set) var saved = HostsFile(parsing: "")
    @Published var draft = HostsFile(parsing: "")
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var saving = false
    @Published private(set) var hasBackup = false

    var isDirty: Bool { draft.text != saved.text }

    func load() {
        do {
            let text = try String(contentsOfFile: HostsFile.path, encoding: .utf8)
            saved = HostsFile(parsing: text)
            draft = saved
            error = nil
        } catch {
            self.error = String(localized: "Hosts dosyası okunamadı: \(error.localizedDescription)")
        }
        hasBackup = FileManager.default.fileExists(atPath: HostsWriter.backupPath)
    }

    func save() async { await write(draft.text, success: String(localized: "Kaydedildi; DNS önbelleği temizlendi.")) }

    func restoreBackup() async {
        guard let text = HostsWriter.backupText else { error = HostsWriteError.noBackup.localizedDescription; return }
        await write(text, success: String(localized: "Önceki hali geri yüklendi."))
    }

    private func write(_ text: String, success: String) async {
        saving = true
        defer { saving = false }
        do {
            try await HostsWriter.write(text)
            load()
            notice = success
        } catch HostsWriteError.cancelled {
            notice = nil
        } catch {
            self.error = error.localizedDescription
            notice = nil
        }
    }

    func add(address: String, hostnames: String, comment: String, group: String?) -> Bool {
        do {
            try draft.add(address: address, hostnames: hostnames, comment: comment, group: group)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct HostsView: View {
    @StateObject private var model = HostsModel()
    @State private var search = ""
    @State private var address = ""
    @State private var hostnames = ""
    @State private var comment = ""
    @State private var group = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Hosts Dosyası",
                              subtitle: "Alan adlarını bir IP’ye yönlendir veya engelle; satırları ve grupları tek tıkla aç/kapat.",
                              icon: "list.bullet.rectangle.portrait") {
                HStack {
                    if model.hasBackup {
                        Button { Task { await model.restoreBackup() } } label: {
                            Label("Önceki hali", systemImage: "clock.arrow.circlepath")
                        }
                        .help("MacPocket’in son kaydetmeden önce aldığı yedeği geri yükle")
                    }
                    Button("Vazgeç") { model.draft = model.saved }.disabled(!model.isDirty)
                    Button { Task { await model.save() } } label: { Label("Kaydet", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.isDirty || model.saving)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if let error = model.error { PocketMessage(error, tone: .warning) }
                    if let notice = model.notice, !model.isDirty { PocketMessage(notice, tone: .success) }
                    if model.isDirty {
                        PocketMessage("Kaydedilmemiş değişiklikler var. Kaydederken macOS yönetici parolasını sorar; önceki dosya yedeklenir.",
                                      tone: .accent)
                    }
                    addForm
                    PocketSearchField("IP, alan adı veya not ara…", text: $search, focus: $searchFocused).frame(maxWidth: 320)
                    ForEach(model.draft.groups) { group in
                        let entries = group.entries.filter(matches)
                        if !entries.isEmpty || (search.isEmpty && group.name != nil) {
                            HostsGroupCard(group: group, entries: entries,
                                           setGroup: { model.draft.setGroupEnabled(group.name, $0) },
                                           setEntry: { model.draft.setEnabled($0, $1) },
                                           remove: { model.draft.remove($0) })
                        }
                    }
                    Text("Kapalı satırlar dosyada # ile yorum satırına çevrilir, silinmez. “## Ad - Start ##” ile “## Ad - End ##” arasındaki satırlar bir grup sayılır. localhost ve broadcasthost satırları macOS için gereklidir ve değiştirilemez.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onAppear { model.load() }
    }

    private func matches(_ entry: HostsEntry) -> Bool {
        search.isEmpty || entry.address.localizedCaseInsensitiveContains(search)
            || entry.hostnames.contains { $0.localizedCaseInsensitiveContains(search) }
            || (entry.comment?.localizedCaseInsensitiveContains(search) ?? false)
    }

    private var groupNames: [String] { model.draft.groups.compactMap(\.name) }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Satır ekle", icon: "plus.circle")
            HStack(spacing: PocketSpacing.s) {
                TextField("IP adresi", text: $address, prompt: Text(verbatim: "127.0.0.1"))
                    .frame(width: 150)
                Button("Engelle") { address = "0.0.0.0" }
                    .buttonStyle(.bordered)
                    .help("0.0.0.0 adresi, alan adına hiçbir yerden ulaşılamamasını sağlar")
                TextField("Alan adları", text: $hostnames, prompt: Text(verbatim: "ornek.local www.ornek.local"))
                TextField("Not", text: $comment).frame(width: 160)
                Menu {
                    Button("Grupsuz") { group = "" }
                    if !groupNames.isEmpty { Divider() }
                    ForEach(groupNames, id: \.self) { name in Button(name) { group = name } }
                } label: {
                    Text(group.isEmpty ? String(localized: "Grupsuz") : group).lineLimit(1)
                }
                .frame(width: 130)
                TextField("veya yeni grup", text: $group).frame(width: 120)
                Button {
                    if model.add(address: address, hostnames: hostnames, comment: comment, group: group.isEmpty ? nil : group) {
                        hostnames = ""; comment = ""
                    }
                } label: { Label("Ekle", systemImage: "plus") }
                .disabled(address.isEmpty || hostnames.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
        }
        .pocketCard()
    }
}

private struct HostsGroupCard: View {
    let group: HostsGroup
    let entries: [HostsEntry]
    let setGroup: (Bool) -> Void
    let setEntry: (UUID, Bool) -> Void
    let remove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack {
                Label {
                    Text(group.name.map { String($0) } ?? String(localized: "Genel")).font(.headline)
                } icon: {
                    Image(systemName: group.name == nil ? "doc.plaintext" : "folder")
                }
                Text(String(localized: "\(group.entries.count) satır")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !group.editable.isEmpty {
                    Toggle(isOn: Binding(get: { group.anyEnabled }, set: setGroup)) { Text("Grubu aç/kapat") }
                        .toggleStyle(.switch).labelsHidden()
                        .help(group.anyEnabled ? "Gruptaki tüm satırları kapat" : "Gruptaki tüm satırları aç")
                }
            }
            if entries.isEmpty {
                Text("Satır yok").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        row(entry)
                    }
                }
            }
        }
        .pocketCard()
    }

    private func row(_ entry: HostsEntry) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Toggle(isOn: Binding(get: { entry.isEnabled }, set: { setEntry(entry.id, $0) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(entry.isSystem)
            Text(verbatim: entry.address).font(.callout.monospaced()).frame(width: 170, alignment: .leading)
                .foregroundStyle(entry.isBlock ? .orange : .primary)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.hostnames.joined(separator: "  ")).lineLimit(2).textSelection(.enabled)
                if let comment = entry.comment { Text(verbatim: comment).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.isSystem {
                Image(systemName: "lock.fill").foregroundStyle(.tertiary).help("macOS için gerekli")
                    .frame(width: 24)
            } else {
                Button { remove(entry.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Satırı sil").accessibilityLabel("Satırı sil")
                    .frame(width: 24)
            }
        }
        .opacity(entry.isEnabled ? 1 : 0.55)
        .padding(.vertical, PocketSpacing.xs)
    }
}
