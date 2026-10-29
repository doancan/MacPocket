import SwiftUI

struct ScreenCleaningView: View {
    @ObservedObject private var controller = ScreenCleaningController.shared
    @State private var seconds = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PocketPageHeading(title: "Ekran Temizleme", subtitle: "Ekranları kısa süreliğine karart, yanlışlıkla tıklamayı önle.", icon: "display")
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Kapsamı bilerek başlat").font(.headline)
                    Text("Tüm bağlı ekranlarda siyah bir MacPocket penceresi açılır. Klavye ve fare girişleri yalnız bu uygulama içinde tutulur; macOS sistem kısayolları kilitlenmez.")
                    Text("Esc ile veya farenin sol düğmesini 2 saniye basılı tutarak çıkabilirsin. Başka uygulamaya geçildiğinde, ekran düzeni değiştiğinde veya süre dolduğunda otomatik kapanır.")
                        .foregroundStyle(.secondary)
                    Picker("Süre", selection: $seconds) {
                        Text("15 saniye").tag(15); Text("30 saniye").tag(30)
                        Text("45 saniye").tag(45); Text("60 saniye").tag(60)
                    }.frame(maxWidth: 300).disabled(controller.phase != .idle)
                    if controller.phase == .countdown {
                        Label("\(controller.remaining) saniye sonra başlayacak…", systemImage: "timer").monospacedDigit()
                        Button("İptal Et") { controller.stop() }.keyboardShortcut(.cancelAction)
                    } else if controller.phase == .active {
                        Button("Temizleme Modunu Kapat") { controller.stop() }
                    } else {
                        Button("3 Saniye Sonra Başlat") { controller.start(seconds: seconds) }
                            .buttonStyle(.borderedProminent)
                    }
                    if let failure = controller.failure { Text(failure).foregroundStyle(.orange) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Fiziksel temizlik sırasında üreticinin önerdiği yöntemi kullan. Bu araç elektriksel kapatma veya tüm sistem girişini kilitleme işlemi yapmaz.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onDisappear { controller.stop() }
    }
}
