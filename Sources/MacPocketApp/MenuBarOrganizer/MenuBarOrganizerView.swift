import AppKit
import MacPocketCore
import SwiftUI

struct MenuBarOrganizerView: View {
    @ObservedObject var service = MenuBarOrganizerService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Menü Çubuğu Düzenleyici", subtitle: "Diğer uygulamaların simgelerini görünür ve gizli gruplara ayır.", icon: "menubar.rectangle") {
                Toggle("Menü çubuğu düzenleyiciyi etkinleştir", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                    .pocketSwitch().labelsHidden()
                    .disabled(!service.isAvailable && !service.enabled)
                    .help("Menü çubuğu düzenleyiciyi etkinleştir")
            }
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                Text("Listeden gizlenecek uygulamaları seç. Ok düğmesi bu simgeleri gizler veya gösterir; sağ tık simge listesini açar. Sıralamak için menü çubuğunda ⌘ basılıyken simgeleri sürükle.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PocketSpacing.s) {
                    Button(LocalizedStringKey(service.collapsed ? "Gizlenen simgeleri göster" : "Simgeleri gizle")) { service.setCollapsed(!service.collapsed) }
                        .disabled(!service.enabled || service.changingVisibility)
                    Button("Listeyi Yenile") { Task { await service.refresh() } }.disabled(service.scanning)
                    if !AXIsProcessTrusted() { Button("Erişilebilirlik İzni Ver") { WindowCatalog.requestAccessibilityPermission() } }
                }
                if !service.isAvailable { Text("Bu macOS sürümünde menü çubuğu görünürlüğü yönetilemiyor.").foregroundStyle(.secondary) }
                Text("Aynı uygulamanın simgeleri birlikte gizlenir. Apple sistem simgeleri ve MacPocket görünür kalır. Düzenleyiciyi kapatmak tüm simgeleri yeniden gösterir.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Bildirim Merkezi gibi sistem panellerini açmadan önce gizli simgeleri göster.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pocketCard()
            MenuBarOrganizerItemList(service: service)
        }.pocketPage()
        .task { await service.refresh() }
    }
}
struct MenuBarOrganizerItemList: View {
    @ObservedObject var service: MenuBarOrganizerService
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSearchField("Simge ara…", text: $search).frame(maxWidth: 360)
            if let error = service.error { Text(error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if service.scanning { PocketProgressRow(message: "Simgeler okunuyor…") }
            let items = service.items.filter { search.isEmpty || "\($0.title) \($0.application)".localizedCaseInsensitiveContains(search) }
            if !items.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            if item.id != items.first?.id { Divider() }
                            row(item)
                        }
                    }
                }
                .pocketCard(padding: PocketSpacing.m)
            }
            if !service.scanning && service.items.isEmpty && service.error == nil { Text("Menü çubuğu simgesi bulunamadı.").foregroundStyle(.secondary) }
        }
    }

    /// One menu bar item: clicking the name opens it; the checkbox moves its app's items into the hidden
    /// group.
    private func row(_ item: ManagedMenuBarItem) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Button { service.open(item) } label: {
                HStack(spacing: PocketSpacing.m) {
                    if let url = item.applicationURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                        Text(item.title).lineLimit(1)
                        Text(item.application).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: PocketSpacing.m)
                    Text(LocalizedStringKey(item.hidden ? "Gizli grup" : "Görünür")).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.application): \(item.title)")
            Toggle("Gizli gruba ekle", isOn: Binding(get: { service.hiddenApplications.contains(item.bundleID) }, set: { service.setHidden($0, for: item.bundleID) }))
                .toggleStyle(.checkbox)
                .disabled(item.bundleID.isEmpty || item.bundleID == Bundle.main.bundleIdentifier || item.bundleID.hasPrefix("com.apple.") || service.changingVisibility)
                .accessibilityLabel("\(item.application) simgelerini gizle")
        }
        .padding(.vertical, PocketSpacing.s)
    }
}
