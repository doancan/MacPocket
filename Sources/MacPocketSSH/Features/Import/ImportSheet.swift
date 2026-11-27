import SSHConfigKit
import SwiftUI

/// Review step of an import: what will be added, what is already there, and what needs attention. Nothing is
/// written until the user confirms, and hosts still go through the save sheet afterwards.
struct ImportSheet: View {
    @Bindable var model: AppModel
    let plan: SSHImportPlan
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(String(localized: "SSH.import.source", defaultValue: "Kaynak")) {
                        Text(verbatim: plan.sourceDirectory.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    if let config = plan.sourceConfig {
                        LabeledContent(String(localized: "SSH.import.config", defaultValue: "Config")) {
                            Text(verbatim: config.lastPathComponent)
                        }
                    }
                }
                if !plan.warnings.isEmpty {
                    Section(String(localized: "SSH.import.warnings", defaultValue: "Dikkat")) {
                        ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                            Label(Self.text(for: warning), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                    }
                }
                Section(hostsTitle) {
                    if plan.hosts.isEmpty {
                        Text(String(localized: "SSH.import.hosts.none", defaultValue: "Eklenecek yeni host yok."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plan.hosts) { host in
                        LabeledContent {
                            Text(verbatim: Self.detail(of: host)).foregroundStyle(.secondary).lineLimit(1)
                        } label: {
                            Label(host.id, systemImage: "server.rack")
                        }
                    }
                    if !plan.skippedHosts.isEmpty {
                        let names = plan.skippedHosts.joined(separator: ", ")
                        Text(String(localized: "SSH.import.hosts.skipped %@", defaultValue: "Zaten tanımlı olduğu için atlanan: \(names)"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(keysTitle) {
                    if plan.keys.isEmpty {
                        Text(String(localized: "SSH.import.keys.none", defaultValue: "Kaynakta özel anahtar bulunamadı."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plan.keys) { key in
                        LabeledContent {
                            Text(verbatim: Self.status(of: key)).foregroundStyle(.secondary)
                        } label: {
                            Label(key.name, systemImage: "key")
                        }
                    }
                    if !plan.keys.isEmpty {
                        Text(String(localized: "SSH.import.keys.note", defaultValue: "Anahtarlar hemen ~/.ssh içine kopyalanır (yalnızca sahibi okuyabilir). Mevcut hiçbir dosyanın üzerine yazılmaz."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if !plan.hosts.isEmpty {
                    Text(String(localized: "SSH.import.hosts.draftNote", defaultValue: "Hostlar değişiklik olarak eklenir; Kaydet’e basana kadar dosyaya yazılmaz."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "SSH.action.cancel", defaultValue: "Vazgeç"), role: .cancel) { model.importPlan = nil }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "SSH.import.confirm", defaultValue: "İçe Aktar")) {
                    working = true
                    Task { await model.confirmImport(); working = false }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(plan.isEmpty || working)
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 520)
    }

    private var hostsTitle: String {
        let count = String(plan.hosts.count)
        return String(localized: "SSH.import.hosts %@", defaultValue: "Hostlar (\(count))")
    }

    private var keysTitle: String {
        let count = String(plan.keys.count)
        return String(localized: "SSH.import.keys %@", defaultValue: "Anahtarlar (\(count))")
    }

    private static func detail(of host: ImportHost) -> String {
        let draft = host.draft
        func value(_ key: String) -> String? { draft.directives.first { $0.key.lowercased() == key.lowercased() }?.value }
        let target = [value("User"), value("HostName")].compactMap { $0 }
        return target.count == 2 ? "\(target[0])@\(target[1])" : target.first ?? ""
    }

    private static func status(of key: ImportKey) -> String {
        switch key.disposition {
        case .copy: String(localized: "SSH.import.key.copy", defaultValue: "Kopyalanacak")
        case .alreadyPresent: String(localized: "SSH.import.key.present", defaultValue: "Zaten var")
        case .renamed(let name): String(localized: "SSH.import.key.renamed %@", defaultValue: "Başka bir anahtar olduğu için “\(name)” adıyla")
        }
    }

    private static func text(for warning: ImportWarning) -> String {
        switch warning {
        case .noConfigFound: String(localized: "SSH.import.warn.noConfig", defaultValue: "Bu klasörde config dosyası ya da anahtar bulunamadı.")
        case .unreadable(let path): String(localized: "SSH.import.warn.unreadable %@", defaultValue: "Okunamadı: \(path)")
        case .notDownloaded(let name): String(localized: "SSH.import.warn.cloud %@", defaultValue: "“\(name)” iCloud’dan henüz indirilmemiş. Finder’da indirip yeniden deneyin.")
        case .notUTF8(let path): String(localized: "SSH.import.warn.notUTF8 %@", defaultValue: "UTF-8 olmayan dosya, içe aktarılamadı: \(path)")
        case .matchBlocksSkipped(let count): String(localized: "SSH.import.warn.match %lld", defaultValue: "\(count) Match bloğu aktarılmaz; gerekirse elle ekleyin.")
        case .missingKey(let host, let path): String(localized: "SSH.import.warn.missingKey %@ %@", defaultValue: "“\(host)” için anahtar bulunamadı: \(path)")
        }
    }
}

/// A button that asks for a folder or config file and starts the import review.
struct ImportButton: View {
    @Bindable var model: AppModel
    var title = String(localized: "SSH.import.choose", defaultValue: "Klasör veya Config Seç…")
    @State private var choosing = false

    var body: some View {
        Button(title) { choosing = true }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder, .data]) { result in
                switch result {
                case .success(let url):
                    // Scoped access is only needed in a sandbox; harmless to request and release.
                    let scoped = url.startAccessingSecurityScopedResource()
                    Task {
                        await model.beginImport(from: url)
                        if scoped { url.stopAccessingSecurityScopedResource() }
                    }
                case .failure(let error):
                    if AppLog.isUserCancel(error) { return }
                    AppLog.error(.settings, error)
                    model.errorMessage = Messages.text(for: error)
                }
            }
    }
}

/// Review step for making the system's ssh read the files this app edits: the exact change to `~/.ssh/config`,
/// the known_hosts lines that would be added, and a backup note. Nothing is written before the user confirms.
struct SystemLinkSheet: View {
    @Bindable var model: AppModel
    let plan: SystemLinkPlan
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(String(localized: "SSH.systemLink.explain", defaultValue: "Terminal, VS Code Remote-SSH ve git yalnızca ~/.ssh içindeki dosyaları okur. Aşağıdaki değişiklikler, MacPocket’ın kullandığı dosyaların onlara da görünmesini sağlar."))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                    Label(Self.text(for: note), systemImage: "info.circle").font(.callout)
                }
                if let change = plan.configChange {
                    Section(String(localized: "SSH.systemLink.config", defaultValue: "~/.ssh/config")) {
                        DiffTextView(hunks: LineDiff.hunks(old: change.old, new: change.new))
                            .frame(minHeight: 120, maxHeight: 200)
                    }
                } else {
                    Section(String(localized: "SSH.systemLink.config", defaultValue: "~/.ssh/config")) {
                        Label(String(localized: "SSH.systemLink.config.done", defaultValue: "Zaten bu dosyayı okuyor."), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section(String(localized: "SSH.systemLink.knownHosts", defaultValue: "~/.ssh/known_hosts")) {
                    if plan.knownHostsToAdd.isEmpty {
                        Label(String(localized: "SSH.systemLink.knownHosts.done", defaultValue: "Eksik kayıt yok."), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        let count = String(plan.knownHostsToAdd.count)
                        Text(String(localized: "SSH.systemLink.knownHosts.add %@", defaultValue: "\(count) kayıt eklenecek. Mevcut kayıtlar silinmez."))
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text(String(localized: "SSH.systemLink.backup", defaultValue: "Değişen dosyaların yedeği önce alınır; Yedekler sekmesinden geri yükleyebilirsiniz."))
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "SSH.action.cancel", defaultValue: "Vazgeç"), role: .cancel) { model.systemLinkPlan = nil }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "SSH.systemLink.apply", defaultValue: "Uygula")) {
                    working = true
                    Task { await model.confirmSystemLink(); working = false }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(plan.isNoop || working)
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 420, idealHeight: 500)
    }

    private static func text(for note: SystemLinkNote) -> String {
        switch note {
        case .sshDirectoryIsSymlink(let target): String(localized: "SSH.systemLink.note.dirLink %@", defaultValue: "~/.ssh bir sembolik bağ; dosyalar şuraya yazılır: \(target)")
        case .configIsSymlink(let target): String(localized: "SSH.systemLink.note.configLink %@", defaultValue: "~/.ssh/config bir sembolik bağ; değişiklik gerçek dosyaya yazılır ve bağ korunur: \(target)")
        case .unreadable(let path): String(localized: "SSH.systemLink.note.unreadable %@", defaultValue: "Okunamadı, bu dosyaya dokunulmaz: \(path)")
        case .notUTF8(let path): String(localized: "SSH.systemLink.note.notUTF8 %@", defaultValue: "UTF-8 olmayan dosyaya dokunulmaz: \(path)")
        }
    }
}
