import ApplicationServices
import MacPocketCore
import SwiftUI

struct ScreenCleaningView: View {
    @ObservedObject private var controller = ScreenCleaningController.shared
    @State private var seconds = 30
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                PocketPageHeading(title: "Ekran Temizleme",
                                  subtitle: "Ekranları kısa süreliğine karart, yanlışlıkla tıklamayı önle.",
                                  icon: "display") {
                    if controller.phase == .active {
                        PocketStatusBadge(text: "Etkin" as LocalizedStringKey, systemImage: "circle.fill", tone: .accent)
                    }
                }
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    PocketSectionHeader("Nasıl çalışır" as LocalizedStringKey, icon: "info.circle")
                    VStack(alignment: .leading, spacing: PocketSpacing.s) {
                        instruction("display.2", "Tüm bağlı ekranlarda siyah bir MacPocket penceresi açılır.")
                        instruction("keyboard", "Varsayılan olarak klavye ve fare girişleri yalnız bu uygulama içinde tutulur; macOS sistem kısayolları kilitlenmez. İstersen aşağıdan tüm girişi kilitleyebilirsin.")
                        instruction("escape", "Esc ile veya farenin sol düğmesini 2 saniye basılı tutarak çık.")
                        instruction("timer", "Süre dolduğunda, başka uygulamaya geçildiğinde veya ekran düzeni değiştiğinde otomatik kapanır.")
                    }
                    Divider()
                    HStack(spacing: PocketSpacing.m) {
                        Picker("Süre", selection: $seconds) {
                            Text("15 saniye").tag(15); Text("30 saniye").tag(30)
                            Text("45 saniye").tag(45); Text("60 saniye").tag(60)
                        }
                        .frame(maxWidth: 240)
                        .disabled(controller.phase != .idle)
                        Spacer(minLength: PocketSpacing.m)
                        action
                    }

                    Divider()
                    HStack(spacing: PocketSpacing.m) {
                        Picker("Renk", selection: $controller.settings.color) {
                            ForEach(CleaningColor.allCases) { Text($0.localizedTitle).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                        .disabled(controller.phase != .idle)
                        .help("Beyaz tozu, siyah parmak izlerini daha iyi gösterir.")
                    }
                    VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                        Toggle("Tüm klavye ve fare girişini kilitle", isOn: $controller.settings.locksInput)
                            .toggleStyle(.switch)
                            .disabled(controller.phase != .idle)
                        Text("Temizlerken yanlışlıkla tuşa basmanı ve imleci oynatmanı engeller. Yalnız Esc ile veya süre dolunca çıkılır.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if controller.settings.locksInput, !trusted {
                            HStack(spacing: PocketSpacing.m) {
                                PocketMessage("Girişi kilitlemek için Erişilebilirlik izni gerekir. İzin verdikten sonra MacPocket’e dönmen yeterli.", tone: .warning)
                                Button("İzin ver…") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                                }
                            }
                        }
                    }
                    if controller.phase == .countdown {

                        PocketProgressRow(message: "\(controller.remaining) saniye sonra başlayacak…" as LocalizedStringKey)
                    }
                    if let failure = controller.failure {
                        PocketMessage(failure, error: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pocketCard()
                Label("Fiziksel temizlikte üreticinin önerdiği yöntemi kullan.", systemImage: "hand.raised")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Bu araç ekranı elektriksel olarak kapatmaz ve tüm sistem girişini kilitlemez.")
            }
        }
        .pocketPage()
        .onDisappear { controller.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
    }

    @ViewBuilder
    private var action: some View {
        switch controller.phase {
        case .countdown:
            Button("İptal Et", role: .cancel) { controller.stop() }
                .keyboardShortcut(.cancelAction)
        case .active:
            Button("Temizleme Modunu Kapat") { controller.stop() }
        default:
            Button {
                controller.start(seconds: seconds)
            } label: {
                Label("3 Saniye Sonra Başlat", systemImage: "play.fill")
            }
            .buttonStyle(.pocketPrimary)
            .help("Geri sayımdan sonra ekranları seçilen süre boyunca karartır")
        }
    }

    private func instruction(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(PocketTheme.accent)
        }
        .font(.callout)
    }
}
