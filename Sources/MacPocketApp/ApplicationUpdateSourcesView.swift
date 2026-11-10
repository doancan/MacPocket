import MacPocketCore
import SwiftUI

struct ApplicationUpdateSourcesView: View {
    @Bindable var model: ApplicationWorkspaceModel
    let working: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text("Güncelleme Kaynakları").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .topLeading)], alignment: .leading, spacing: PocketSpacing.m) {
                ForEach(ApplicationUpdateSource.allCases) { source in
                    VStack(alignment: .leading, spacing: PocketSpacing.s) {
                        Toggle(source.localizedTitle, isOn: Binding(get: { model.updateSettings.sources.contains(source) }, set: { on in
                            if on { model.updateSettings.sources.insert(source) } else { model.updateSettings.sources.remove(source) }
                        })).toggleStyle(.switch).accessibilityLabel(Text(source.localizedTitle)).disabled(working)
                        if !model.updateSettings.sources.contains(source) { Text("Kapalı").font(.caption).foregroundStyle(.secondary) }
                        else if model.currentUpdateSource == source {
                            Label("Denetleniyor…", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                        } else if let result = model.updateSourceResults[source] {
                            Text("\(result.checked) eşleşme · \(result.unmatched) bulunamadı · \(result.skipped) atlandı").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if !result.failures.isEmpty {
                                DisclosureGroup("Kaynak hataları") {
                                    Text(result.failures.prefix(3).joined(separator: "\n")).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }.font(.caption).foregroundStyle(PocketTone.warning.color)
                            }
                        } else { Text("Henüz denetlenmedi").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            if model.updateSettings.sources.contains(.appStore) {
                HStack {
                    TextField("Mağaza ülke kodu", text: Binding(get: { model.updateSettings.country }, set: { model.updateSettings.country = $0.uppercased() }))
                        .textFieldStyle(.roundedBorder).frame(width: 70).disabled(working)
                    Text("App Store ülkenin iki harfli kodu; örneğin TR veya US.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.updateSettings.sources.contains(.sparkle) {
                Toggle("Ön sürüm kanallarını dahil et", isOn: $model.updateSettings.includePrereleases).disabled(working)
            }
            Text("App Store denetimi Apple’a uygulama kimliklerini gönderir. Uygulama içi denetim üreticinin güncelleme listesini okur. Denetim elle başlatılır; Homebrew ile yönetilen uygulamalar kendi kaynağında kalır.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Denetim ve kurulum hakkında") {
                Text("App Store sonucu mağazada açılır; uygulama içi sonuçta uygulamayı açıp kendi Güncellemeleri Denetle komutunu kullan. Setapp ve diğer üretici kanalları kendi araçlarından yönetilir.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Homebrew denetimi yerel kataloğu kullanır; paket kataloğunu kendiliğinden yenilemez.")
                    .fixedSize(horizontal: false, vertical: true)
            }.font(.caption).foregroundStyle(.secondary)
            if model.updateSettings.sources.isEmpty {
                Text("Denetlemek için en az bir kaynak seç.").font(.callout).foregroundStyle(.secondary)
            }
        }.pocketCard(padding: PocketSpacing.m, radius: PocketRadius.medium)
    }
}
