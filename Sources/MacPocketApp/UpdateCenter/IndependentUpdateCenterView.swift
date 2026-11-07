import MacPocketCore
import SwiftUI

struct IndependentUpdateCenterView: View {
    @StateObject private var model = IndependentUpdateCenterModel()
    @State private var search = ""
    @State private var editing: InstalledApplication?
    @State private var repository = ""
    @State private var sourceError = false
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Güncelleme Merkezi", subtitle: "Homebrew dışındaki uygulamaların sürümlerini üretici kaynaklarıyla karşılaştır.", icon: "arrow.triangle.2.circlepath") {
                if model.checking { Button("Vazgeç", action: model.cancel) }
                else { Button("Güncellemeleri Denetle") { Task { await model.check() } }.disabled(model.loading || model.applications.isEmpty) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle("App Store uygulamalarını dahil et", isOn: $model.includeAppStore).disabled(model.checking)
                Toggle("Ön sürümleri dahil et", isOn: $model.includePrereleases).disabled(model.checking)
                Text("Sparkle listeleri üreticiden okunur. GitHub için uygulamaya bir depo bağla. App Store seçilirse uygulama kimlikleri Apple’a gönderilir. Denetim yalnız düğmeyle başlatılır.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Kurulum için uygulamanın kendi güncelleyicisi veya üreticinin sürüm sayfası açılır. Homebrew uygulamaları Uygulamalar bölümünden yönetilir.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.pocketCard()
            if model.checking { ProgressView("Güncelleme kaynakları denetleniyor…") }
            if model.loading { ProgressView("Kurulu uygulamalar okunuyor…") }
            if model.cancelled { Text("Denetim iptal edildi; eksik sonuçlar güncel kabul edilmez.").foregroundStyle(.secondary) }
            if let date = model.checkedAt {
                Text("\(model.checked) uygulama denetlendi · \(model.findings.count) güncelleme").font(.headline)
                Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.findings) { finding in
                HStack {
                    PocketAppIcon(url: finding.app.url, size: 32)
                    VStack(alignment: .leading) { Text(finding.app.name).font(.headline); Text("\(finding.installed) → \(finding.available)"); Text(finding.source).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(LocalizedStringKey(finding.releaseURL == nil ? "Uygulamayı Aç" : "Sürümü Aç")) { model.open(finding) }
                }.pocketCard()
            }
            if !model.failures.isEmpty { DisclosureGroup("Denetim hataları") { ForEach(Array(model.failures.enumerated()), id: \.offset) { _, message in Text(message).textSelection(.enabled) } } }
            TextField("Uygulama ara…", text: $search).textFieldStyle(.roundedBorder)
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.applications.filter { search.isEmpty || "\($0.name) \($0.bundleID)".localizedCaseInsensitiveContains(search) }) { app in
                    HStack {
                        PocketAppIcon(url: app.url, size: 24)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(model.repositories[app.bundleID] ?? (app.channel == .sparkle ? String(localized: "Üreticinin Sparkle kaynağı") : app.channel.localizedTitle)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("GitHub Kaynağı") { editing = app; repository = model.repositories[app.bundleID] ?? ""; sourceError = false }.disabled(model.checking)
                    }
                }
            }
            if model.loaded && model.applications.isEmpty && !model.checking { Text("Bağımsız uygulama bulunamadı.").foregroundStyle(.secondary) }
        }.pocketPage()
        .task { await model.load() }
        .onDisappear { model.cancel() }
        .sheet(item: $editing) { app in
            VStack(alignment: .leading, spacing: 16) {
                Text(app.name).font(.headline)
                TextField("GitHub deposu: sahibi/depo", text: $repository).textFieldStyle(.roundedBorder)
                Text("Yalnız uygulamanın üreticisine ait depoyu kullan. Sürüm etiketleri kurulu sürümle karşılaştırılır.").font(.caption).foregroundStyle(.secondary)
                if sourceError { Text("Geçerli bir GitHub depo adresi veya sahibi/depo gir.").foregroundStyle(.red) }
                HStack {
                    Button("Vazgeç") { editing = nil }
                    if model.repositories[app.bundleID] != nil { Button("Kaynağı Kaldır") { _ = model.saveRepository(for: app.bundleID, value: nil); editing = nil } }
                    Spacer()
                    Button("Kaydet") {
                        if model.saveRepository(for: app.bundleID, value: repository) { editing = nil } else { sourceError = true }
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 460)
        }
    }
}
