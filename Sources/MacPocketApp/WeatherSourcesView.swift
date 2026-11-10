import MacPocketCore
import SwiftUI

struct WeatherSourcePicker: View {
    var service: WeatherService = .shared
    @State private var expanded: Bool
    init(service: WeatherService = .shared, initiallyExpanded: Bool = false) {
        self.service = service; _expanded = State(initialValue: initiallyExpanded)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Picker("Veri Kaynağı", selection: Binding(get: { service.activeSource }, set: service.selectSource)) {
                ForEach(service.basket.orderedSources) { source in Text(source.localizedTitle).tag(source) }
            }.pickerStyle(.menu).weatherAuditTarget("weather.source-picker")
            if service.activeSource.requiresAPIKey && !service.configuredKeys.contains(service.activeSource) {
                Label("API anahtarı gerekiyor; Kaynak Sepeti’nden ekleyebilirsin.", systemImage: "key")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $expanded) {
                WeatherSourcesView(service: service).padding(.top, PocketSpacing.s)
            } label: { Text("Kaynak Sepeti").weatherAuditTarget("weather.basket") }
                .font(.callout)
        }
    }
}

struct WeatherSourcesView: View {
    var service: WeatherService
    @State private var accountsExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text("İstediğin kaynakları sepete ekle, ardından gösterilecek kaynağı seç. Yalnız seçili kaynaktan veri alınır.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if service.activeSource.requiresAPIKey { accounts }
            group("Anahtarsız kaynaklar", sources: [.visualCrossing, .metNorway, .openMeteo])
            DisclosureGroup {
                group("Ayrı model seçimi", sources: [.ecmwf, .ecmwfAI, .gfs, .icon])
                    .padding(.top, PocketSpacing.s)
            } label: { Text("Open-Meteo modelleri").weatherAuditTarget("weather.models") }
            Text("Open-Meteo’nun ücretsiz sunucusu ticari olmayan kullanım içindir. Ayrı modeller aynı sağlayıcının kotasını paylaşır.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !service.activeSource.requiresAPIKey { accounts }
            if service.basket.sources.contains(.istatLegacy) {
                WeatherSourceRow(source: .istatLegacy, service: service)
            }
            Text("Ücretsiz kotalar sağlayıcı hesabına aittir. Koşullar değişebilir; kaynak bağlantısından güncel kapsamı kontrol edebilirsin.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = service.credentialError { PocketMessage(error, tone: .warning) }
        }.onAppear { accountsExpanded = service.activeSource.requiresAPIKey }
            .onChange(of: service.activeSource) { if service.activeSource.requiresAPIKey { accountsExpanded = true } }
    }
    private var accounts: some View {
        DisclosureGroup(isExpanded: $accountsExpanded) {
            group("Kendi API anahtarınla", sources: accountSources)
                .padding(.top, PocketSpacing.s)
        } label: { Text("Ücretsiz hesapla kullanılan kaynaklar").weatherAuditTarget("weather.accounts") }
    }
    private var accountSources: [WeatherSource] {
        let sources: [WeatherSource] = [.weatherAPI, .pirateWeather, .openWeather, .tomorrow]
        return service.activeSource.requiresAPIKey ? [service.activeSource] + sources.filter { $0 != service.activeSource } : sources
    }
    private func group(_ title: LocalizedStringKey, sources: [WeatherSource]) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            ForEach(sources) { source in WeatherSourceRow(source: source, service: service) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeatherSourceRow: View {
    let source: WeatherSource
    var service: WeatherService
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            Toggle(isOn: Binding(get: { service.basket.sources.contains(source) }, set: { service.include(source, included: $0) })) {
                Text(source.localizedTitle).font(.callout.weight(.medium))
            }.toggleStyle(.checkbox)
                .disabled(service.basket.sources.count == 1 && service.basket.sources.contains(source))
                .help("Sepette en az bir kaynak kalmalıdır.")
                .weatherAuditTarget("weather.source." + source.rawValue)
            Text(source.freeTierDescription).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Kapsam ve Koşullar", destination: source.informationURL).font(.caption).buttonStyle(.borderless)
            if source.requiresAPIKey && service.basket.sources.contains(source) {
                if service.configuredKeys.contains(source) {
                    HStack {
                        Label("Anahtar kaydedildi", systemImage: "key.fill").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Anahtarı Sil", role: .destructive) { service.saveKey(nil, for: source) }.controlSize(.small)
                    }
                }
                SecureField("API anahtarı", text: $key).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(source.localizedTitle) API anahtarı")
                    .weatherAuditTarget("weather.key." + source.rawValue)
                HStack {
                    Text("Anahtar yalnız bu Mac’in Anahtar Zinciri’nde saklanır.").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Anahtarı Kaydet") { if service.saveKey(key, for: source) { key = "" } }
                        .controlSize(.small).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(.leading, PocketSpacing.xs)
    }
}
