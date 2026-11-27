import SSHConfigKit
import SwiftUI

struct BackupsView: View {
    @State private var backups: BackupsModel
    @State private var confirmingRestore: Backup?
    /// The backup and the known_hosts revision/store the confirmation was opened for.
    @State private var confirmingKnownHostsRestore: (backup: Backup, seen: BackupsModel.KnownHostsSnapshot)?

    init(model: AppModel) {
        _backups = State(initialValue: BackupsModel(model: model))
    }

    var body: some View {
        GeometryReader { bounds in
        HSplitView {
            VStack(spacing: 0) {
                Picker(String(localized: "SSH.settings.backups", defaultValue: "Yedekler"), selection: $backups.fileKind) {
                    Text(String(localized: "SSH.backups.kind.config", defaultValue: "SSH config")).tag(BackupFileKind.config)
                    Text(String(localized: "SSH.backups.kind.knownHosts", defaultValue: "known_hosts")).tag(BackupFileKind.knownHosts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
            List(selection: $backups.selectedURL) {
                ForEach(backups.backups, id: \.url) { backup in
                    Text(backup.date.formatted(date: .abbreviated, time: .standard)).tag(backup.url)
                }
            }
            .overlay {
                if backups.backups.isEmpty {
                    ContentUnavailableView(String(localized: "SSH.backups.empty", defaultValue: "Henüz yedek yok."), systemImage: "clock.arrow.circlepath")
                }
            }
            }
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
            Group {
            if let backup = backups.selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "SSH.backups.diffCaption", defaultValue: "Mevcut dosyadan bu yedeğe değişiklikler")).font(.headline)
                    DiffTextView(hunks: backups.hunks(for: backup))
                    HStack {
                        if backups.fileKind == .config {
                            Text(String(localized: "SSH.backups.restore.note", defaultValue: "Yedek kaydedilmemiş değişiklik olarak yüklenir; uygulamak için inceleyip kaydedin.")).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(String(localized: "SSH.backups.restore", defaultValue: "Düzenleyiciye Yükle")) {
                            if backups.fileKind == .knownHosts {
                                confirmingKnownHostsRestore = (backup, backups.knownHostsSnapshot())
                            } else if backups.model.store.hasUnsavedChanges || backups.model.hasPendingFormEdits {
                                confirmingRestore = backup
                            } else {
                                restore(backup)
                            }
                        }
                        .disabled(restoreDisabled)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView(String(localized: "SSH.settings.backups", defaultValue: "Yedekler"), systemImage: "clock.arrow.circlepath")
            }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(width: bounds.size.width, height: bounds.size.height)
        .clipped()
        }
        .frame(minWidth: 0, minHeight: 320)
        .onAppear { backups.refresh() }
        .onChange(of: ObjectIdentifier(backups.model.store)) { backups.refresh() }
        .onChange(of: backups.model.store.diskText) { backups.refresh() }
        .onChange(of: backups.model.knownHosts.revision) { backups.refresh() }
        .onChange(of: ObjectIdentifier(backups.model.knownHosts)) {
            confirmingKnownHostsRestore = nil
            if backups.fileKind == .knownHosts { backups.selectedURL = nil }
            backups.refresh()
        }
        .alert(
            String(localized: "SSH.error.title", defaultValue: "Bir Sorun Oluştu"),
            isPresented: Binding(get: { backups.alertMessage != nil }, set: { if !$0 { backups.alertMessage = nil } })
        ) {
            Button(String(localized: "SSH.action.close", defaultValue: "Kapat")) { backups.alertMessage = nil }
        } message: {
            Text(backups.alertMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "SSH.backups.restore.knownHosts.title", defaultValue: "known_hosts dosyası bu yedekle değiştirilsin mi?"),
            isPresented: Binding(get: { confirmingKnownHostsRestore != nil }, set: { if !$0 { confirmingKnownHostsRestore = nil } }),
            presenting: confirmingKnownHostsRestore
        ) { pending in
            Button(String(localized: "SSH.backups.restore.confirm.action", defaultValue: "Değiştir"), role: .destructive) { restore(pending.backup, seen: pending.seen) }
        } message: { _ in
            Text(String(localized: "SSH.backups.restore.knownHosts.message", defaultValue: "Dosya hemen yazılır. Mevcut dosyanın önce yedeği alınır."))
        }
        .confirmationDialog(
            String(localized: "SSH.backups.restore.confirm.title", defaultValue: "Kaydedilmemiş değişiklikleriniz bu yedekle değiştirilsin mi?"),
            isPresented: Binding(get: { confirmingRestore != nil }, set: { if !$0 { confirmingRestore = nil } }),
            presenting: confirmingRestore
        ) { backup in
            Button(String(localized: "SSH.backups.restore.confirm.action", defaultValue: "Değiştir"), role: .destructive) { restore(backup) }
        }
    }

    private var restoreDisabled: Bool {
        switch backups.fileKind {
        case .config:
            backups.model.store.loadState != .loaded && backups.model.store.loadState != .missing
        case .knownHosts:
            backups.model.knownHosts.loadState != .loaded && backups.model.knownHosts.loadState != .missing
        }
    }

    private func restore(_ backup: Backup, seen: BackupsModel.KnownHostsSnapshot? = nil) {
        backups.performRestore(backup, seen: seen)
    }
}
