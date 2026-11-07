import MacPocketCore
import SwiftUI

struct SwitcherGlobalCardOptions: View {
    @AppStorage("switcher.titleMode") private var titleMode = SwitcherTitleMode.standard.rawValue
    @AppStorage("switcher.truncation") private var truncation = SwitcherTitleTruncation.tail.rawValue
    @AppStorage("switcher.showStatus") private var showStatus = true
    @AppStorage("switcher.showSpaces") private var showSpaces = false
    @AppStorage("switcher.showActions") private var showActions = true
    @AppStorage("switcher.showThumbnails") private var showThumbnails = true
    var body: some View {
        Picker("Başlık", selection: $titleMode) { ForEach(SwitcherTitleMode.allCases, id: \.self) { Text($0.localizedTitle).tag($0.rawValue) } }
        Picker("Başlığı kısalt", selection: $truncation) { ForEach(SwitcherTitleTruncation.allCases, id: \.self) { Text($0.localizedTitle).tag($0.rawValue) } }
        Toggle("Durum simgeleri", isOn: $showStatus)
        Toggle("Masaüstü numaraları", isOn: $showSpaces)
        SwitcherBadgeSettings()
        Toggle("Fare üzerindeyken pencere düğmeleri", isOn: $showActions)
        Toggle("Küçük resimleri göster", isOn: $showThumbnails)
        SwitcherCardOptionsNote()
    }
}

struct SwitcherGlobalPlacementOptions: View {
    @AppStorage("switcher.screen") private var screen = SwitcherScreenPolicy.pointer.rawValue
    @AppStorage("switcher.openingDelayMilliseconds") private var delay = 110
    var body: some View {
        Picker("Paneli göster", selection: $screen) { ForEach(SwitcherScreenPolicy.allCases, id: \.self) { Text($0.localizedTitle).tag($0.rawValue) } }
        let bounded = SwitcherPresentation.boundedDelay(Double(delay))
        Stepper("Açılma gecikmesi: \(bounded) ms", value: Binding(get: { SwitcherPresentation.boundedDelay(Double(delay)) },
            set: { delay = SwitcherPresentation.boundedDelay(Double($0)) }), in: 0...900, step: 10)
        SwitcherPlacementNote()
    }
}

struct SwitcherGlobalMotionOptions: View {
    @AppStorage("switcher.animateOpening") private var opening = true
    @AppStorage("switcher.animateClosing") private var closing = false
    @AppStorage("switcher.animateSelection") private var selection = true
    @AppStorage("switcher.animatePreview") private var preview = false
    var body: some View {
        Toggle("Panel açılışı", isOn: $opening)
        Toggle("Panel kapanışı", isOn: $closing)
        Toggle("Seçim animasyonu", isOn: $selection)
        Toggle("Tam boy önizleme girişi", isOn: $preview)
        SwitcherMotionNote()
    }
}

struct SwitcherCardOptionsNote: View {
    var body: some View {
        Text("Küçük resimler kapalıysa küçük resim stili uygulama simgelerini gösterir ve küçük resim yakalamaz. Tam boy önizleme ayarı ayrıdır. Tam adlar yardım metninde ve erişilebilirlik adında korunur.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
struct SwitcherPlacementNote: View {
    var body: some View {
        Text("Öndeki pencerenin ekranı belirlenemezse farenin ekranı kullanılır. Ekran filtresi panelin gösterildiği ekrana bağlıdır. Gecikme yalnız basılı tutarak açılışı bekletir; hızlı bırakma seçimi bekletmez.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
struct SwitcherMotionNote: View {
    var body: some View {
        Text("Hareketi azalt açıkken bu animasyonlar kullanılmaz. Seçim ve klavye işlemleri animasyonun bitmesini beklemez.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct SwitcherBadgeNote: View {
    var body: some View {
        Text("Rozet uygulamanın Dock etiketidir; pencereye özel okunmamış sayısı değildir. Panel açıkken yenilenir. Dock etiketi veya Erişilebilirlik izni yoksa rozet gösterilmez. Uzun etiketin tamamı yardım metninde ve erişilebilirlik açıklamasındadır.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
    }
}

struct SwitcherBadgeSettings: View {
    @AppStorage private var enabled: Bool
    init(defaults: UserDefaults = .standard) { _enabled = AppStorage(wrappedValue: true,"switcher.showBadges",store: defaults) }
    var body: some View {
        Toggle("Dock bildirim rozetleri",isOn: $enabled)
        SwitcherBadgeNote()
    }
}
