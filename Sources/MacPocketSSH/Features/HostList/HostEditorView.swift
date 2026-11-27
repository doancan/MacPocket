import SSHConfigKit
import SwiftUI

struct HostEditorView: View {
    @Bindable var editor: HostEditorModel
    let homeDirectory: URL
    let keys: KeysModel
    /// IdentityFile values whose private key has no passphrase; their rows get a lock-open hint.
    var unencryptedKeys: Set<String> = []
    let reload: () -> Void
    @State private var importingIdentity = false

    var body: some View {
        Form {
            if editor.isStale {
                Section {
                    Label(String(localized: "SSH.editor.stale", defaultValue: "Bu host düzenleyici dışında değiştirildi."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button(String(localized: "SSH.editor.stale.reload", defaultValue: "Host'u Yeniden Yükle"), action: reload)
                }
            }
            Section(String(localized: "SSH.editor.section.connection", defaultValue: "Bağlantı")) {
                TextField(String(localized: "SSH.editor.alias", defaultValue: "Alias"), text: $editor.aliasText)
                field("HostName", help: String(localized: "SSH.help.HostName", defaultValue: "Bağlanılacak gerçek sunucu adı veya IP adresi."))
                field("User", help: String(localized: "SSH.help.User", defaultValue: "Sunucudaki kullanıcı adı."))
                field("Port", help: String(localized: "SSH.help.Port", defaultValue: "SSH portu (varsayılan 22)."))
                field("ProxyJump", help: String(localized: "SSH.help.ProxyJump", defaultValue: "Üzerinden bağlanılacak ara sunucu(lar)."))
                Picker(selection: binding("ForwardAgent")) {
                    Text(String(localized: "SSH.editor.forwardAgent.unset", defaultValue: "Ayarlanmamış")).tag("")
                    Text(verbatim: "yes").tag("yes")
                    Text(verbatim: "no").tag("no")
                } label: {
                    Text(verbatim: "ForwardAgent")
                }
                .help(String(localized: "SSH.help.ForwardAgent", defaultValue: "Yerel ssh-agent'ı sunucuya ilet."))
            }

            Section(String(localized: "SSH.editor.identityFiles", defaultValue: "Anahtar Dosyaları")) {
                ForEach(Array(editor.identityFiles.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField(String(localized: "SSH.editor.identityFiles", defaultValue: "Anahtar Dosyaları"), text: identityBinding(index))
                            .labelsHidden()
                        if editor.identityFiles.indices.contains(index), unencryptedKeys.contains(editor.identityFiles[index]) {
                            Image(systemName: "lock.open.fill")
                                .foregroundStyle(.orange)
                                .help(String(localized: "SSH.keys.passphrase.noHelp", defaultValue: "Bu özel anahtarın parolası yok. Dosyayı kopyalayan herkes kullanabilir."))
                                .accessibilityLabel(String(localized: "SSH.keys.passphrase.noHelp", defaultValue: "Bu özel anahtarın parolası yok. Dosyayı kopyalayan herkes kullanabilir."))
                        }
                        Button(String(localized: "SSH.editor.remove", defaultValue: "Kaldır"), systemImage: "minus.circle") {
                            if editor.identityFiles.indices.contains(index) { editor.identityFiles.remove(at: index) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button(String(localized: "SSH.editor.identityFiles.add", defaultValue: "Anahtar Dosyası Ekle")) { editor.identityFiles.append("") }
                    Menu(String(localized: "SSH.action.choose", defaultValue: "Seç…")) {
                        let privateKeys = keys.rows.filter { $0.key.hasPrivateKey && !$0.key.unreadable }
                        if privateKeys.isEmpty {
                            Text(String(localized: "SSH.editor.identityFiles.noKeys", defaultValue: "Anahtar bulunamadı"))
                        }
                        ForEach(privateKeys) { row in
                            Button {
                                if !editor.identityFiles.contains(row.displayPath) { editor.identityFiles.append(row.displayPath) }
                            } label: {
                                Text(verbatim: row.displayPath)
                            }
                        }
                        Divider()
                        Button(String(localized: "SSH.editor.identityFiles.otherFile", defaultValue: "Başka Dosya…")) { importingIdentity = true }
                    }
                    .fixedSize()
                    .task { await keys.refreshIfStale() }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        Task { await keys.refreshIfStale() }
                    }
                }
            }

            Section(String(localized: "SSH.editor.otherOptions", defaultValue: "Diğer Seçenekler")) {
                ForEach(Array(editor.otherOptions.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField(String(localized: "SSH.editor.otherOptions.key", defaultValue: "Seçenek"), text: optionBinding(index, \.key))
                        TextField(String(localized: "SSH.editor.otherOptions.value", defaultValue: "Değer"), text: optionBinding(index, \.value))
                        Button(String(localized: "SSH.editor.remove", defaultValue: "Kaldır"), systemImage: "minus.circle") {
                            if editor.otherOptions.indices.contains(index) { editor.otherOptions.remove(at: index) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Button(String(localized: "SSH.editor.otherOptions.add", defaultValue: "Seçenek Ekle")) {
                    editor.otherOptions.append(DraftDirective(key: "", value: ""))
                }
            }

            if !editor.issues.isEmpty || editor.failure != nil {
                Section(String(localized: "SSH.editor.issues", defaultValue: "Sorunlar")) {
                    ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in
                        Label(Messages.text(for: issue), systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isBlocking ? .red : .orange)
                    }
                    if let error = editor.failure {
                        Label(Messages.text(for: error), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: editor.draft) { editor.commit() }
        .fileImporter(isPresented: $importingIdentity, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                let path = url.standardizedFileURL.path
                let home = homeDirectory.standardizedFileURL.path
                editor.identityFiles.append(path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
            }
        }
    }

    private func field(_ key: String, help: String) -> some View {
        TextField(key, text: binding(key))
            .help(help)
    }

    /// Bounds-safe: a row can outlive its element for one render after a removal.
    private func identityBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { editor.identityFiles.indices.contains(index) ? editor.identityFiles[index] : "" },
            set: { if editor.identityFiles.indices.contains(index) { editor.identityFiles[index] = $0 } })
    }

    private func optionBinding(_ index: Int, _ keyPath: WritableKeyPath<DraftDirective, String>) -> Binding<String> {
        Binding(
            get: { editor.otherOptions.indices.contains(index) ? editor.otherOptions[index][keyPath: keyPath] : "" },
            set: { if editor.otherOptions.indices.contains(index) { editor.otherOptions[index][keyPath: keyPath] = $0 } })
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { editor.fields[key] ?? "" }, set: { editor.fields[key] = $0 })
    }
}
