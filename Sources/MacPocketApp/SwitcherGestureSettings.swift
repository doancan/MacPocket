import MacPocketCore
import SwiftUI

struct SwitcherGestureSettings: View {
    let isAvailable: Bool
    @AppStorage private var fingers: Int
    @AppStorage private var axis: String
    @AppStorage private var haptics: Bool
    init(isAvailable: Bool,defaults: UserDefaults = .standard) {
        self.isAvailable = isAvailable
        _fingers = AppStorage(wrappedValue: 0,SwitcherGestureOptions.fingersKey,store: defaults)
        _axis = AppStorage(wrappedValue: SwitcherGestureAxis.horizontal.rawValue,SwitcherGestureOptions.axisKey,store: defaults)
        _haptics = AppStorage(wrappedValue: false,SwitcherGestureOptions.hapticsKey,store: defaults)
    }
    var body: some View {
        Picker("Hareket",selection: Binding(get: { fingers == 3 || fingers == 4 ? fingers : 0 },set: { fingers = $0 })) {
            Text("Kapalı").tag(0)
            Text("Üç parmakla kaydır").tag(3)
            Text("Dört parmakla kaydır").tag(4)
        }.pickerStyle(.radioGroup).disabled(!isAvailable)
        Picker("Kaydırma yönü",selection: Binding<SwitcherGestureAxis>(get: { .init(rawValue: axis) ?? .horizontal },set: { axis = $0.rawValue })) {
            ForEach(SwitcherGestureAxis.allCases,id: \.self) { Text($0.localizedTitle).tag($0) }
        }.pickerStyle(.radioGroup).disabled(!isAvailable || fingers != 3 && fingers != 4)
        Toggle("Seçim değiştiğinde haptik geri bildirim",isOn: $haptics)
            .disabled(!isAvailable || fingers != 3 && fingers != 4)
        Text("Yatay hareket pencereler, dikey hareket satırlar arasında gezinir. Son parmağı kaldırmak seçer; arama başladıysa panel açık kalır. Escape vazgeçer. Haptik geri bildirim, destekleyen trackpad’lerde hareketle seçim değiştiğinde verilir.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
        Text(isAvailable
             ? "macOS aynı hareketi masaüstleri veya Mission Control için kullanıyorsa Sistem Ayarları > Trackpad > Diğer Hareketler’den değiştir. Hareketler yalnız global geçiş açıkken ve öndeki uygulamada izin veriliyorken çalışır. Ayar değişikliği devam eden hareketi iptal eder."
             : "Bu macOS sürümünde trackpad hareket verisine erişilemiyor.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
    }
}
