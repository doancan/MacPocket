import AppKit
import MacPocketCore
import SwiftUI

struct MenuBarOrganizerView: View {
    @ObservedObject var service = MenuBarOrganizerService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Menü Çubuğu Düzenleyici", subtitle: "Diğer uygulamaların simgelerini görünür ve gizli gruplara ayır.", icon: "menubar.rectangle")
            VStack(alignment: .leading, spacing: PocketSpacing.m) {
                Toggle("Menü çubuğu düzenleyiciyi etkinleştir", isOn: Binding(get: { service.enabled }, set: service.setEnabled)).disabled(!service.isAvailable && !service.enabled)
                Text("Listeden gizlenecek uygulamaları seç. Ok düğmesi bu simgeleri gizler veya gösterir; sağ tık simge listesini açar. Sıralamak için menü çubuğunda ⌘ basılıyken simgeleri sürükle.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(LocalizedStringKey(service.collapsed ? "Gizlenen simgeleri göster" : "Simgeleri gizle")) { service.setCollapsed(!service.collapsed) }
                        .disabled(!service.enabled || service.changingVisibility)
                    Button("Listeyi Yenile") { Task { await service.refresh() } }.disabled(service.scanning)
                    if !AXIsProcessTrusted() { Button("Erişilebilirlik İzni Ver") { WindowCatalog.requestAccessibilityPermission() } }
                }
                if !service.isAvailable { Text("Bu macOS sürümünde menü çubuğu görünürlüğü yönetilemiyor.").foregroundStyle(.secondary) }
                Text("Aynı uygulamanın simgeleri birlikte gizlenir. Apple sistem simgeleri ve MacPocket görünür kalır. Düzenleyiciyi kapatmak tüm simgeleri yeniden gösterir.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Bildirim Merkezi gibi sistem panellerini açmadan önce gizli simgeleri göster.").font(.caption).foregroundStyle(.secondary)
            }.pocketCard()
            MenuBarOrganizerItemList(service: service)
        }.pocketPage()
        .task { await service.refresh() }
    }
}
struct MenuBarOrganizerItemList: View {
    @ObservedObject var service: MenuBarOrganizerService
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Simge ara…", text: $search).textFieldStyle(.roundedBorder)
            if let error = service.error { Text(error).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if service.scanning { ProgressView("Simgeler okunuyor…") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(service.items.filter { search.isEmpty || "\($0.title) \($0.application)".localizedCaseInsensitiveContains(search) }) { item in
                        Button { service.open(item) } label: {
                            HStack {
                                if let url = item.applicationURL { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22) }
                                VStack(alignment: .leading) { Text(item.title).lineLimit(1); Text(item.application).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(LocalizedStringKey(item.hidden ? "Gizli grup" : "Görünür")).font(.caption).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(item.application): \(item.title)")
                        Toggle("Gizli gruba ekle", isOn: Binding(get: { service.hiddenApplications.contains(item.bundleID) }, set: { service.setHidden($0, for: item.bundleID) }))
                            .disabled(item.bundleID.isEmpty || item.bundleID == Bundle.main.bundleIdentifier || item.bundleID.hasPrefix("com.apple.") || service.changingVisibility)
                            .accessibilityLabel("\(item.application) simgelerini gizle")
                    }
                }
            }
            if !service.scanning && service.items.isEmpty && service.error == nil { Text("Menü çubuğu simgesi bulunamadı.").foregroundStyle(.secondary) }
        }.padding(12)
    }
}
