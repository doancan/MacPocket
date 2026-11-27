import AppKit
import MacPocketCore
import MacPocketNetworkPolicy
import SwiftUI

struct InternetControlView: View {
    @StateObject private var model = InternetControlModel()
    @State private var confirmReset = false
    var body: some View {
        // Scrolls: the connection list alone can run to hundreds of rows.
        ScrollView {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "İnternet Kontrolü", subtitle: "İmzalı uygulama kimliğine göre yeni ağ bağlantılarına izin ver veya engelle.", icon: "network")
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Filtre", icon: "shield") { EmptyView() }
                if model.configurationKnown {
                    Label(LocalizedStringKey(model.enabled ? "Filtre yapılandırması etkin" : "Filtre yapılandırması kapalı"), systemImage: model.enabled ? "checkmark.shield" : "shield")
                } else { Label("Filtre durumu doğrulanamadı", systemImage: "shield") }
                if let message = model.message { Text(message).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary) }
                if model.busy { ProgressView("Sistem yapılandırması bekleniyor…") }
                HStack(spacing: PocketSpacing.s) {
                    Button("Uzantıyı Etkinleştir", action: model.activate).disabled(!model.packaged || model.busy)
                    Button("Kuralları Uygula") { Task { await model.apply(enabled: true) } }.disabled(!model.packaged || model.busy || !model.extensionReady || !model.policyReadable)
                    Button("Filtreyi Kapat") { Task { await model.apply(enabled: false) } }.disabled(!model.packaged || model.busy || !model.enabled)
                    Spacer(minLength: PocketSpacing.s)
                    Button("Sistem Ağ Ayarlarını Aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                }
                Text("Filtre için macOS ağ uzantısı izni gerekir. Yeni kurallar açık bağlantıları geriye dönük kesmez. İmzalı uygulama güncellendiğinde kurallar aynı geliştirici kimliğini izler; ad-hoc imzalı uygulama değiştiğinde yeniden eklenmelidir.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Uygulama kuralları", icon: "app.badge.checkmark") {
                    Button("Uygulama Ekle…", action: model.addApplication).disabled(model.busy || !model.policyReadable)
                }
                if !model.policyReadable { Button("Ağ Kurallarını Sıfırla", role: .destructive) { confirmReset = true } }
                if !model.policy.rules.isEmpty && !model.policyApplied { Text("Bu kurallar henüz filtreye uygulanmadı.").foregroundStyle(.secondary) }
                if model.policy.rules.isEmpty { Text("Kural yok. Kuralı olmayan uygulamalara izin verilir.").foregroundStyle(.secondary) }
                ForEach(model.policy.rules) { rule in
                    if rule.id != model.policy.rules.first?.id { Divider() }
                    HStack(spacing: PocketSpacing.m) {
                        VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                            Text(rule.name).font(.body.weight(.medium))
                            Text(rule.identity.identifier).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: PocketSpacing.m)
                        Picker("İnternet erişimi", selection: Binding(get: { rule.action }, set: { model.setAction($0, for: rule.id) })) {
                            Text("İzin Ver").tag(AppNetworkAction.allow)
                            Text("Engelle").tag(AppNetworkAction.deny)
                        }.frame(maxWidth: 180, alignment: .trailing).disabled(model.busy)
                            .pocketMenuPicker()
                        Button("Kaldır") { model.remove(rule.id) }.disabled(model.busy)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                PocketSectionHeader("Açık bağlantılar", icon: "point.3.connected.trianglepath.dotted") {
                    Button("Bağlantıları Yenile") { Task { await model.refreshConnections() } }.disabled(model.readingConnections)
                }
                Text("Bu kullanıcıya görünür TCP/UDP bağlantıları gösterilir; sistem süreçlerinin bir kısmı görünmeyebilir.").font(.caption).foregroundStyle(.secondary)
                if model.readingConnections { ProgressView("Bağlantılar okunuyor…") }
                else if model.connectionsLoaded && model.connections.isEmpty { Text("Görünür bağlantı bulunamadı.").foregroundStyle(.secondary) }
                if !model.connections.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(model.connections) { group in
                            ConnectionGroupRow(group: group)
                            if group.id != model.connections.last?.id { Divider() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
        }
        .padding(PocketSpacing.page)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task { await model.reload(); await model.refreshConnections() }
        .confirmationDialog("Kayıtlı ağ kuralları silinsin mi?", isPresented: $confirmReset) {
            Button("Ağ Kurallarını Sıfırla", role: .destructive, action: model.resetUnreadablePolicy)
        }
    }
}

/// One process and its connections: a count up front, the endpoints one click away.
private struct ConnectionGroupRow: View {
    let group: OpenConnection.Group
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                ForEach(group.connections, id: \.self) { connection in
                    HStack(spacing: PocketSpacing.s) {
                        Text(verbatim: connection.local).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                        Text(verbatim: connection.remote)
                        Spacer(minLength: 0)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.leading, PocketSpacing.l)
            .padding(.vertical, PocketSpacing.xs)
        } label: {
            HStack {
                Text(verbatim: group.process).font(.body.weight(.medium))
                Text(verbatim: "PID \(group.pid)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text("\(group.connections.count) bağlantı").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, PocketSpacing.xs)
    }
}
