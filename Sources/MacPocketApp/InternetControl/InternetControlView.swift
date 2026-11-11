import AppKit
import MacPocketCore
import MacPocketNetworkPolicy
import SwiftUI

struct InternetControlView: View {
    @StateObject private var model = InternetControlModel()
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "İnternet Kontrolü", subtitle: "İmzalı uygulama kimliğine göre yeni ağ bağlantılarına izin ver veya engelle.", icon: "network")
            VStack(alignment: .leading, spacing: 12) {
                if model.configurationKnown {
                    Label(LocalizedStringKey(model.enabled ? "Filtre yapılandırması etkin" : "Filtre yapılandırması kapalı"), systemImage: model.enabled ? "checkmark.shield" : "shield")
                } else { Label("Filtre durumu doğrulanamadı", systemImage: "shield") }
                if let message = model.message { Text(message).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary) }
                if model.busy { ProgressView("Sistem yapılandırması bekleniyor…") }
                HStack {
                    Button("Uzantıyı Etkinleştir", action: model.activate).disabled(!model.packaged || model.busy)
                    Button("Kuralları Uygula") { Task { await model.apply(enabled: true) } }.disabled(!model.packaged || model.busy || !model.extensionReady || !model.policyReadable)
                    Button("Filtreyi Kapat") { Task { await model.apply(enabled: false) } }.disabled(!model.packaged || model.busy || !model.enabled)
                }
                Button("Sistem Ağ Ayarlarını Aç") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
                }
                Text("Filtre için macOS ağ uzantısı izni gerekir. Yeni kurallar açık bağlantıları geriye dönük kesmez. İmzalı uygulama güncellendiğinde kurallar aynı geliştirici kimliğini izler; ad-hoc imzalı uygulama değiştiğinde yeniden eklenmelidir.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.pocketCard()
            HStack { Text("Uygulama kuralları").font(.headline); Spacer(); Button("Uygulama Ekle…", action: model.addApplication).disabled(model.busy || !model.policyReadable) }
            if !model.policyReadable { Button("Ağ Kurallarını Sıfırla", role: .destructive) { confirmReset = true } }
            if !model.policy.rules.isEmpty && !model.policyApplied { Text("Bu kurallar henüz filtreye uygulanmadı.").foregroundStyle(.secondary) }
            if model.policy.rules.isEmpty { Text("Kural yok. Kuralı olmayan uygulamalara izin verilir.").foregroundStyle(.secondary) }
            ForEach(model.policy.rules) { rule in
                HStack {
                    VStack(alignment: .leading) { Text(rule.name).font(.headline); Text(rule.identity.identifier).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Picker("İnternet erişimi", selection: Binding(get: { rule.action }, set: { model.setAction($0, for: rule.id) })) {
                        Text("İzin Ver").tag(AppNetworkAction.allow); Text("Engelle").tag(AppNetworkAction.deny)
                    }.frame(maxWidth: 180).disabled(model.busy)
                        .pocketMenuPicker()
                    Button("Kaldır") { model.remove(rule.id) }.disabled(model.busy)
                }.pocketCard()
            }
            HStack { Text("Açık bağlantılar").font(.headline); Spacer(); Button("Bağlantıları Yenile") { Task { await model.refreshConnections() } }.disabled(model.readingConnections) }
            if model.readingConnections { ProgressView("Bağlantılar okunuyor…") }
            else if model.connectionsLoaded && model.connections.isEmpty { Text("Görünür bağlantı bulunamadı.").foregroundStyle(.secondary) }
            Text("Bu kullanıcıya görünür TCP/UDP bağlantıları gösterilir; sistem süreçlerinin bir kısmı görünmeyebilir.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(model.connections.enumerated()), id: \.offset) { _, row in Text(row).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
        }.pocketPage().task { await model.reload(); await model.refreshConnections() }
        .confirmationDialog("Kayıtlı ağ kuralları silinsin mi?", isPresented: $confirmReset) {
            Button("Ağ Kurallarını Sıfırla", role: .destructive, action: model.resetUnreadablePolicy)
        }
    }
}
