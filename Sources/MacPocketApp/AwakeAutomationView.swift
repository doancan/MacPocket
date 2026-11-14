import AppKit
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

struct AwakeAutomationView: View {
    @ObservedObject var service: AwakeAutomationService
    @State private var selectionError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Toggle("Koşullu uyanık tutma", isOn: $service.settings.enabled)
                .toggleStyle(.switch).accessibilityLabel("Koşullu uyanık tutma")
            if service.settings.enabled {
                Text(service.ownedSessionID != nil ? String(localized: "Koşullu uyanık tutma etkin") : service.status.localizedTitle)
                    .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Picker("Koşullar", selection: $service.settings.match) {
                    ForEach(AwakeAutomationMatch.allCases) { Text($0.localizedTitle).tag($0) }
                }.accessibilityLabel("Koşullar")
                    .pocketMenuPicker()
                ForEach(AwakeAutomationCondition.allCases) { condition in
                    HStack {
                        Toggle(condition.localizedTitle, isOn: Binding(get: { service.settings.conditions.contains(condition) }, set: { on in
                            if on { service.settings.conditions.insert(condition) } else { service.settings.conditions.remove(condition) }
                        })).toggleStyle(.checkbox).accessibilityLabel(Text(condition.localizedTitle))
                        if service.settings.conditions.contains(condition) {
                            Text(service.matching.contains(condition) ? "Sağlandı" : "Bekleniyor").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if service.settings.conditions.contains(.applicationRunning) {
                    ForEach(service.settings.applicationIDs.sorted(), id: \.self) { id in
                        HStack {
                            Text(verbatim: service.settings.applicationNames[id] ?? id).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Button {
                                var settings = service.settings
                                settings.applicationIDs.remove(id); settings.applicationNames.removeValue(forKey: id)
                                service.settings = settings
                            } label: { Label("Kaldır", systemImage: "minus.circle") }.labelStyle(.iconOnly).help("Kaldır")
                        }.font(.callout)
                    }
                    Button("Uygulama Seç…", action: chooseApp).disabled(service.settings.applicationIDs.count >= 128)
                    if service.settings.applicationIDs.isEmpty {
                        Text("Uygulama koşulunu kullanmak için en az bir uygulama seç.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Otomasyonun süre sınırı", selection: $service.settings.maximumMinutes) {
                    Text("30 dakika").tag(30); Text("1 saat").tag(60); Text("2 saat").tag(120)
                    Text("4 saat").tag(240); Text("8 saat").tag(480)
                    Divider()
                    Text("7 gün (en uzun)").tag(10_080)
                }.accessibilityLabel("Otomasyonun süre sınırı")
                    .pocketMenuPicker()
                Toggle("Otomasyonda ekranı da açık tut", isOn: $service.settings.keepDisplayAwake)
                Toggle("Oturum kilitliyken duraklat", isOn: $service.settings.pauseWhenLocked)
                Text("Koşullar bitince otomasyon durur. Süre sınırı, kilitte geçen süreyi de kapsar; koşullar yeniden sağlanmadan kendiliğinden yenilenmez.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if service.status == .manualPause || service.status == .limitReached {
                    Button("Otomasyonu Yeniden Değerlendir") { service.resume() }
                }
            }
            Text("Elle başlatma ve durdurma önceliklidir. Otomasyon, koşullar önce bozulup yeniden sağlanana kadar bekler; elle başlatılan oturumu değiştirmez.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = service.error {
                PocketMessage(error, tone: .warning)
                Button("Yeniden Dene") { service.resume() }
            }
            if let selectionError { PocketMessage(selectionError, tone: .warning) }
        }
    }
    private func chooseApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Koşula Ekle")
        guard panel.runModal() == .OK else { return }
        var settings = service.settings
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, ApplicationUpdateURL.validBundleID(id) else {
                selectionError = String(localized: "Seçilen paketin uygulama kimliği okunamadı."); continue
            }
            guard settings.applicationIDs.count < 128 || settings.applicationIDs.contains(id) else { break }
            settings.applicationIDs.insert(id)
            settings.applicationNames[id] = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        }
        service.settings = settings
    }
}
