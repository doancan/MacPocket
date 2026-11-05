import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.sshNavigate) private var navigate
    private enum ImportTarget { case config, knownHosts }
    @State private var importing = false
    @State private var lastImportTarget: ImportTarget?
    @State private var knownHostsInvalid = false
    @State private var pendingPath: String?
    @State private var invalidMessage: String?

    var body: some View {
        Form {
            general
            files
            backups
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.data]
        ) { result in
            let url: URL
            switch result {
            case .success(let picked): url = picked
            case .failure(let error):
                if AppLog.isUserCancel(error) { return }
                AppLog.error(.settings, error)
                switch lastImportTarget {
                case .config: invalidMessage = String(localized: "SSH.settings.configFile.invalid", defaultValue: "Mutlak yolu olan bir dosya seçin.")
                case .knownHosts: knownHostsInvalid = true
                case nil: break
                }
                return
            }
            guard let target = lastImportTarget else { return }
            let path = model.settings.displayPath(for: url)
            switch target {
            case .config: requestSwitch(path)
            case .knownHosts: switchKnownHosts(path)
            }
        }
        .confirmationDialog(
            String(localized: "SSH.settings.switch.title", defaultValue: "Kaydedilmemiş değişiklikler kaydedilsin mi?"),
            isPresented: Binding(get: { pendingPath != nil }, set: { if !$0 { pendingPath = nil } }),
            presenting: pendingPath
        ) { path in
            Button(String(localized: "SSH.settings.switch.save", defaultValue: "Kaydet ve Değiştir")) {
                Task {
                    switch await model.saveThenSwitchConfig(to: path) {
                    case .switched: invalidMessage = nil
                    case .invalid: invalidMessage = String(localized: "SSH.settings.configFile.invalid", defaultValue: "Mutlak yolu olan bir dosya seçin.")
                    case .failed(let message): invalidMessage = message
                    }
                }
            }
            Button(String(localized: "SSH.settings.switch.discard", defaultValue: "At ve Değiştir"), role: .destructive) {
                _ = model.switchConfig(to: path, discardingUnsavedChanges: true)
            }
        }
    }

    @ViewBuilder private var general: some View {
        Section(String(localized: "SSH.settings.connection", defaultValue: "Bağlantı")) {
            Picker(String(localized: "SSH.settings.terminal", defaultValue: "Terminal"), selection: Binding(
                get: { model.settings.terminal }, set: { model.settings.setTerminal($0) }
            )) {
                ForEach(TerminalChoice.allCases, id: \.self) { choice in
                    let name = choice.displayName
                    Text(verbatim: model.isTerminalInstalled(choice) ? name : String(localized: "SSH.settings.terminal.notInstalled %@", defaultValue: "\(name) (yüklü değil)"))
                        .tag(choice).selectionDisabled(!model.isTerminalInstalled(choice))
                }
            }
            KeyboardShortcuts.Recorder(String(localized: "SSH.settings.shortcut", defaultValue: "Hızlı Bağlan kısayolu"), name: .quickConnect)
        }
    }

    @ViewBuilder private var files: some View {
        Section(String(localized: "SSH.settings.configFile", defaultValue: "Config Dosyası")) {
            LabeledContent(String(localized: "SSH.settings.configFile", defaultValue: "Config Dosyası")) {
                Text(verbatim: model.settings.configPath).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).help(model.settings.configPath)
            }
            HStack {
                Button(String(localized: "SSH.action.choose", defaultValue: "Seç…")) { lastImportTarget = .config; importing = true }
                Button(String(localized: "SSH.settings.configFile.useDefault", defaultValue: "~/.ssh/config Kullan")) { requestSwitch(AppSettings.defaultConfigPath) }
                    .disabled(model.commandBuilder.usesDefaultConfig)
            }
            if let invalidMessage {
                Text(verbatim: invalidMessage).font(.footnote).foregroundStyle(.red)
            }
            if !model.commandBuilder.usesDefaultConfig {
                Text(String(localized: "SSH.settings.configFile.customNote", defaultValue: "Terminalde doğrudan “ssh host” yazarsanız bu dosya kullanılmaz; uygulama -F ile bağlanır."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section(String(localized: "SSH.settings.knownHostsFile", defaultValue: "known_hosts dosyası")) {
            LabeledContent(String(localized: "SSH.settings.knownHostsFile", defaultValue: "known_hosts dosyası")) {
                Text(verbatim: model.settings.knownHostsPath).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).help(model.settings.knownHostsPath)
            }
            HStack {
                Button(String(localized: "SSH.action.choose", defaultValue: "Seç…")) { lastImportTarget = .knownHosts; importing = true }
                Button(String(localized: "SSH.settings.knownHostsFile.useDefault", defaultValue: "~/.ssh/known_hosts kullan")) {
                    switchKnownHosts(AppSettings.defaultKnownHostsPath)
                }
                .disabled(model.settings.knownHostsPath == AppSettings.defaultKnownHostsPath)
            }
            if knownHostsInvalid {
                Text(String(localized: "SSH.settings.knownHostsFile.invalid", defaultValue: "Bu yol kullanılamaz. Mutlak bir yol seçin.")).font(.footnote).foregroundStyle(.red)
            }
            if model.settings.knownHostsPath != AppSettings.defaultKnownHostsPath {
                Text(String(localized: "SSH.settings.knownHostsFile.customNote", defaultValue: "ssh, config'inizde UserKnownHostsFile ayarlı değilse yine ~/.ssh/known_hosts okur."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var backups: some View {
        Section(String(localized: "SSH.settings.backups", defaultValue: "Yedekler")) {
            let count = String(model.settings.backupCount)
            Stepper(
                value: Binding(get: { model.settings.backupCount }, set: { model.setBackupCount($0) }),
                in: AppSettings.backupCountRange
            ) {
                Text(String(localized: "SSH.settings.backups.count %@", defaultValue: "Saklanacak yedek sayısı: \(count)"))
            }
            Button(String(localized: "SSH.settings.backups.show", defaultValue: "Yedekleri Göster…")) { navigate(.backups) }
        }
    }

    private func switchKnownHosts(_ path: String) {
        knownHostsInvalid = !model.switchKnownHosts(to: path)
    }

    private func requestSwitch(_ path: String) {
        invalidMessage = nil
        switch model.switchConfig(to: path) {
        case .needsConfirmation: pendingPath = path
        case .invalid: invalidMessage = String(localized: "SSH.settings.configFile.invalid", defaultValue: "Mutlak yolu olan bir dosya seçin.")
        case .switched, .unchanged: break
        }
    }
}
