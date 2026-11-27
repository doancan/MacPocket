import MacPocketCore
import SwiftUI

struct SwitcherCursorSettings: View {
    @AppStorage private var policy: String
    init(defaults: UserDefaults = .standard) { _policy = AppStorage(wrappedValue: SwitcherCursorPolicy.never.rawValue,SwitcherCursorPolicy.key,store: defaults) }
    var body: some View {
        Picker("İmleç seçimi izlesin", selection: Binding(get: { SwitcherCursorPolicy(rawValue: policy) ?? .never },set: { policy = $0.rawValue })) {
            ForEach(SwitcherCursorPolicy.allCases,id: \.self) { Text($0.localizedTitle).tag($0) }
        }.pickerStyle(.radioGroup)
        Text("Başarılı geçişten sonra imleç, odaktaki pencerenin görünür bölümünün ortasına taşınır. Geçiş sırasında yeni bir tuşa basar, fareyi hareket ettirir, tıklar veya kaydırırsan taşıma yapılmaz. Ekran koşulu imlecin ve pencerenin ekranını karşılaştırır. Değişiklik sonraki panel açılışında uygulanır.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
    }
}
