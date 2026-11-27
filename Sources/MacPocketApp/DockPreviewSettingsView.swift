import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

struct DockPreviewSettingsView: View {
    @ObservedObject private var service = DockPreviewService.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Dock Önizlemeleri", subtitle: "Dock simgesinde bekle; uygulamanın pencerelerini gör, seç ve yerleştir.", icon: "dock.rectangle")
                Form {
                    Section("Davranış") {
                        Toggle("Dock pencere önizlemelerini aç", isOn: $service.settings.enabled)
                            .accessibilityLabel("Dock pencere önizlemelerini aç")
                            .accessibilityIdentifier("dock-preview.enabled")
                        LabeledContent("Açılma gecikmesi") {
                            Stepper("\(service.settings.hoverDelayMilliseconds) ms", value: $service.settings.hoverDelayMilliseconds, in: 100...1200, step: 50)
                                .accessibilityLabel("Açılma gecikmesi")
                        }
                        LabeledContent("Kapanma gecikmesi") {
                            Stepper("\(service.settings.hideDelayMilliseconds) ms", value: $service.settings.hideDelayMilliseconds, in: 100...1200, step: 50)
                                .accessibilityLabel("Kapanma gecikmesi")
                        }
                        Toggle("Yalnız geçerli masaüstünün pencereleri", isOn: $service.settings.currentSpaceOnly)
                            .accessibilityLabel("Yalnız geçerli masaüstünün pencereleri")
                        Text("Dock’un alt, sol ve sağ konumu izlenir. Panele geçerken Dock gizlense de önizleme açık kalır.").foregroundStyle(.secondary)
                    }
                    Section("Pencere görselleri") {
                        Toggle("Pencere görsellerini göster", isOn: $service.settings.thumbnails)
                            .accessibilityLabel("Pencere görsellerini göster")
                        Toggle("Panel açıkken görselleri yenile", isOn: $service.settings.live)
                            .accessibilityLabel("Panel açıkken görselleri yenile").disabled(!service.settings.thumbnails)
                        Text("Yalnız görünür kartlar yakalanır. Görseller bellekte tutulur ve panel kapanınca bırakılır.").foregroundStyle(.secondary)
                    }
                    Section("İzinler") {
                        if !service.trusted {
                            Label("Dock simgelerini okumak ve pencere işlemleri için Erişilebilirlik izni gerekli.", systemImage: "lock")
                            Button("Erişilebilirlik İzni Ver…") { service.requestAccessibility() }
                        } else {
                            Label("Erişilebilirlik izni verildi", systemImage: "checkmark.circle")
                        }
                        if service.settings.thumbnails, !service.captureAllowed {
                            Text("Ekran Kaydı izni olmadan başlık ve uygulama simgeleri gösterilir; pencere görselleri alınmaz.")
                            Button("Ekran Kaydı İzni Ver…") { WindowPreviewProvider.requestPermission(); service.updatePermissions() }
                        }
                        Button("İzin Durumunu Yenile") { service.updatePermissions() }
                        if service.monitorFailed {
                            Text("Fare izleyicisi başlatılamadı. Önizlemeyi kapatıp yeniden açmayı dene.").foregroundStyle(.orange)
                        }
                    }
                    Section("Hariç tutulan uygulamalar") {
                        if service.settings.excludedPaths.isEmpty { Text("Tüm uygulamalar dahil").foregroundStyle(.secondary) }
                        ForEach(service.settings.excludedPaths, id: \.self) { path in
                            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                            HStack {
                                Text(name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { service.settings.excludedPaths.removeAll { $0 == path } } label: { Image(systemName: "minus.circle") }
                                    .accessibilityLabel("Hariç tutmayı kaldır: \(name)")
                            }
                        }
                        Button("Uygulama Ekle…") { chooseApplication() }
                    }
                    Section("Kullanım") {
                        Text("Bir karta tıklayarak pencereye geç. Kartın altındaki düğmelerle küçült, geri aç, kapat veya yerleştir.")
                        Text("Paneli tıkladıktan sonra oklarla seç, Enter ile pencereye geç, Escape ile paneli kapat. Pencere Geçişi kısayolları da kullanılabilir.")
                        Text("Diğer masaüstlerindeki pencereler macOS’un bildirdiği ölçüde gösterilir. Küçültülmüş veya yakalanamayan pencerelerde uygulama simgesi kullanılır.")
                    }
                }
                .pocketFormPage()
                // Sits on the page backdrop like the rest of the window, not on an opaque sheet.
                .scrollContentBackground(.hidden)
            }
            .padding(PocketSpacing.page)
        }
        .onAppear { service.updatePermissions() }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            if response == .OK {
                MainActor.assumeIsolated { service.settings.excludedPaths = Array(Set(service.settings.excludedPaths + panel.urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })).sorted() }
            }
        }
    }
}
