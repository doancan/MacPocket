import MacPocketCore
import SwiftUI

struct PowerManagementView: View {
    @ObservedObject var model: PocketModel
    @State private var minutes = 30.0
    @State private var displayAwake = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PocketPageHeading(title: "Güç Merkezi", subtitle: "Enerji durumu, uyku yönetimi ve yerel güç geçmişi.", icon: "battery.100percent.bolt")
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(model.system?.power.source ?? "Güç kaynağı okunuyor", systemImage: model.system?.power.batteryPresent == true ? "battery.100percent" : "powerplug")
                            .font(.title2.weight(.semibold))
                        if model.system?.power.batteryPresent == true {
                            Text(model.system?.power.chargePercent.map { String(format: "Pil %.0f%%", $0) } ?? "Pil seviyesi okunamıyor").font(.largeTitle.monospacedDigit())
                            Text(model.system?.power.isCharging == true ? "Şarj oluyor" : "Şarj olmuyor").foregroundStyle(.secondary)
                        } else {
                            Text("Bu Mac’te dahili pil bulunmuyor.").font(.headline)
                            Text("Şarj sınırı ve pil sağlığı kontrolleri bu cihazda kullanılamıyor. Uyku yönetimi ve güç geçmişi çalışır.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Divider()
                        LabeledContent("Güç modu", value: model.system?.power.lowPowerMode == true ? "Düşük güç" : "Standart")
                        LabeledContent("Termal durum", value: model.system?.thermalState == "nominal" ? "Normal" : (model.system?.thermalState ?? "—"))
                        Button("Sistem Güç Raporlarını Aç") { model.navigation.open(.diagnostics) }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Uyku Yönetimi", systemImage: "moon.zzz").font(.headline)
                        if let session = model.awakeSession, session.active {
                            Label("Mac uyanık tutuluyor", systemImage: "cup.and.saucer.fill").foregroundStyle(PocketTheme.accent)
                            if let end = session.endsAt { Text("Bitiş \(end.formatted(date: .omitted, time: .shortened))").font(.callout) }
                            Text(session.keepDisplayAwake ? "Ekran açık tutuluyor." : "Ekran normal davranır.").font(.callout).foregroundStyle(.secondary)
                            Button("Uyanık Tutmayı Durdur") { Task { await model.stopAwake() } }
                        } else {
                            Picker("Süre", selection: $minutes) {
                                Text("15 dakika").tag(15.0); Text("30 dakika").tag(30.0)
                                Text("1 saat").tag(60.0); Text("2 saat").tag(120.0)
                            }
                            Toggle("Ekranı da açık tut", isOn: $displayAwake)
                            Button("Uyanık Tutmayı Başlat") { Task { await model.startAwake(duration: minutes * 60, display: displayAwake) } }
                                .buttonStyle(.borderedProminent)
                        }
                        Text("Otomatik uyku geçici olarak engellenir. Süre sonunda veya uygulamadan çıkıldığında sona erer.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = model.awakeError { Text(error).font(.caption).foregroundStyle(.orange) }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                }
                history
            }.padding(24)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Güç Geçmişi", systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
                Text("Yerel kayıt · dakikada bir").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.powerHistoryError { Text(error).font(.caption).foregroundStyle(.orange) }
            if model.powerHistory.isEmpty {
                Text("İlk ölçüm bekleniyor. Pil bulunan cihazlarda şarj yüzdesi de kaydedilir.").foregroundStyle(.secondary)
            } else {
                let charge = model.powerHistory.suffix(180).compactMap(\.chargePercent)
                if charge.count > 1 { PocketGraph(values: charge, color: PocketTheme.disk).frame(height: 100) }
                ForEach(model.powerHistory.suffix(12).reversed()) { entry in
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).frame(width: 175, alignment: .leading)
                        Text(entry.source)
                        Spacer()
                        if let percent = entry.chargePercent { Text(String(format: "%.0f%%", percent)).monospacedDigit() }
                        Text(entry.event == "sample" ? (entry.thermalState == "nominal" ? "Normal" : entry.thermalState) : entry.event)
                            .foregroundStyle(.secondary)
                    }.font(.callout)
                    Divider()
                }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}
