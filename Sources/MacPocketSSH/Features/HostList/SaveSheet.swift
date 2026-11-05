import SSHConfigKit
import SwiftUI

/// Review → save, or resolve a conflict. `finish(true)` means the document was reloaded from disk.
struct SaveSheet: View {
    @Bindable var flow: SaveFlowModel
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch flow.phase {
            case .preparing:
                ProgressView(String(localized: "SSH.save.validating", defaultValue: "ssh ile doğrulanıyor…"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .review(let preparation):
                Text(String(localized: "SSH.save.title", defaultValue: "Değişiklikleri İncele")).font(.headline)
                DiffTextView(hunks: preparation.hunks).frame(minWidth: 640, minHeight: 320)
                validation(preparation.validation)
                Text(String(localized: "SSH.save.sshNote", defaultValue: "Doğrulama “ssh -G” çalıştırır; bu, dosyadaki “Match exec” komutlarını da çalıştırır ve sunucu adlarını sorgulayabilir."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(String(localized: "SSH.action.cancel", defaultValue: "Vazgeç")) { finish(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "SSH.action.save", defaultValue: "Kaydet")) { Task { await flow.confirm() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!flow.canConfirm)
                }
            case .saving:
                ProgressView(String(localized: "SSH.save.saving", defaultValue: "Kaydediliyor…"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .conflict:
                Text(String(localized: "SSH.conflict.title", defaultValue: "Dosya Diskte Değişti")).font(.headline)
                Text(String(localized: "SSH.conflict.message", defaultValue: "Dosya açıldıktan sonra başka bir program tarafından değiştirildi. Hangi sürümün kalacağını seçin."))
                if let unreadable = flow.conflictUnreadableMessage {
                    Text(unreadable)
                        .textSelection(.enabled)
                        .frame(minWidth: 640, minHeight: 120, alignment: .topLeading)
                } else {
                    DiffTextView(hunks: flow.conflictHunks()).frame(minWidth: 640, minHeight: 280)
                }
                HStack {
                    Button(String(localized: "SSH.conflict.loadDisk", defaultValue: "Diskteki Sürümü Yükle (Benimkileri At)"), role: .destructive) {
                        flow.loadDiskVersion()
                        finish(true)
                    }
                    Spacer()
                    Button(String(localized: "SSH.action.cancel", defaultValue: "Vazgeç")) { finish(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "SSH.conflict.overwrite", defaultValue: "Üzerine Yaz")) { Task { await flow.overwrite() } }
                        .disabled(flow.conflictUnreadableMessage != nil)
                }
            case .failed(let message):
                Text(String(localized: "SSH.save.failed.title", defaultValue: "Kaydedilemedi")).font(.headline)
                Text(message).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button(String(localized: "SSH.save.retry", defaultValue: "Tekrar Dene")) { Task { await flow.prepare() } }
                    Button(String(localized: "SSH.action.close", defaultValue: "Kapat")) { finish(false) }
                        .keyboardShortcut(.defaultAction)
                }
            case .done:
                Color.clear.frame(width: 1, height: 1)
                    .onAppear { finish(false) }
            }
        }
        .padding()
        .task { if flow.phase == .preparing { await flow.prepare() } }
    }

    @ViewBuilder
    private func validation(_ outcome: ValidationOutcome) -> some View {
        let valid = outcome == .valid
        Label(Messages.text(for: outcome), systemImage: valid ? "checkmark.seal.fill" : "xmark.octagon.fill")
            .foregroundStyle(valid ? .green : .red)
            .font(valid ? .body : .system(.body, design: .monospaced))
            .textSelection(.enabled)
    }
}
