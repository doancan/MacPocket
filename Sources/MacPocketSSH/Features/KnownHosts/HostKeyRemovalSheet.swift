import SSHConfigKit
import SwiftUI

struct HostKeyRemovalSheet: View {
    let model: AppModel
    let removal: HostKeyRemoval

    var body: some View {
        let alias = removal.alias
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "SSH.hostKeyRemoval.title %@", defaultValue: "“\(alias)” için known_hosts kayıtları")).font(.headline)
            switch removal.phase {
            case .resolving:
                HStack { ProgressView().controlSize(.small); Text(String(localized: "SSH.hostKeyRemoval.resolving", defaultValue: "ssh'e bu host'un hangi ad ve portu kullandığı soruluyor…")) }
            case .confirm(let entries):
                Text(String(localized: "SSH.hostKeyRemoval.confirm.message", defaultValue: "Bu kayıtlar silinecek. Önce yedek alınır.")).foregroundStyle(.secondary)
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: Self.names(of: entry)).fontWeight(.medium)
                        Text(verbatim: "\(entry.keyType)  \(Fingerprint.sha256(base64Key: entry.keyBase64) ?? "")")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120)
            case .nothingFound(let names):
                let joined = names.joined(separator: ", ")
                Text(String(localized: "SSH.hostKeyRemoval.nothingFound %@", defaultValue: "\(joined) ile eşleşen known_hosts kaydı yok."))
            case .failed(let message):
                Text(verbatim: message).foregroundStyle(.red)
            }
            ForEach(removal.notes, id: \.self) { note in
                Label { Text(verbatim: note) } icon: { Image(systemName: "info.circle") }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(String(localized: "SSH.action.cancel", defaultValue: "Vazgeç"), role: .cancel) { model.cancelHostKeyRemoval() }
                    .keyboardShortcut(.cancelAction)
                if case .confirm = removal.phase {
                    Button(String(localized: "SSH.knownHosts.delete", defaultValue: "Sil"), role: .destructive) { model.confirmHostKeyRemoval() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private static func names(of entry: KnownHostEntry) -> String {
        entry.names.map { name in
            switch name {
            case .plain(let address): address.port == 22 ? address.host : "[\(address.host)]:\(address.port)"
            case .hashed: String(localized: "SSH.knownHosts.hashed", defaultValue: "(hash'li kayıt)")
            }
        }.joined(separator: ", ")
    }
}
