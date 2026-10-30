import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

/// Tools → Ekran Parlaklığı: per-display brightness and contrast for external monitors, and the keyboard keys.
struct DisplayBrightnessView: View {
    @ObservedObject private var service = DisplayBrightnessService.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekran Parlaklığı",
                              subtitle: "Harici monitörlerin parlaklığını klavyenin parlaklık tuşlarıyla, dahili ekran gibi ayarla.",
                              icon: "sun.max.fill") {
                Button { Task { await service.refreshDisplays() } } label: { Label("Yeniden algıla", systemImage: "arrow.clockwise") }
                    .disabled(service.detecting)
            }
            if service.settings.keysEnabled && !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Parlaklık tuşlarını yakalamak için Erişilebilirlik izni gerekir. İzin verdikten sonra MacPocket’e dönmen yeterli.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if service.displays.isEmpty {
                        ContentUnavailableView(service.detecting ? "Ekranlar algılanıyor…" : "Harici ekran yok",
                                               systemImage: "display",
                                               description: Text("Dahili ekranın parlaklığını macOS yönetir."))
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .pocketCard()
                    }
                    ForEach(service.displays) { display in DisplayCard(display: display, service: service) }
                    keys
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Klavye", icon: "keyboard") {
                if service.tapActive {
                    PocketStatusBadge(text: "Etkin", systemImage: "checkmark.circle.fill", tone: .success)
                }
            }
            Toggle("Parlaklık tuşları harici ekranları da ayarlasın", isOn: $service.settings.keysEnabled)
            Picker("Hangi ekran", selection: $service.settings.target) {
                Text("İmlecin bulunduğu ekran").tag(DisplayBrightnessService.Target.underPointer)
                Text("Tüm harici ekranlar").tag(DisplayBrightnessService.Target.allExternal)
                Text("Ana ekran").tag(DisplayBrightnessService.Target.main)
            }
            .frame(maxWidth: 380)
            .disabled(!service.settings.keysEnabled)
            Toggle("macOS parlaklık göstergesini göster", isOn: $service.settings.showIndicator)
                .disabled(!service.settings.keysEnabled || !BrightnessIndicator.isNative)
            Text("Dahili gibi 16 adımda değişir; ⌥⇧ ile birlikte basınca dörtte bir adım ilerler. İmleç dahili ekrandayken tuşlar her zamanki gibi macOS’a gider.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

private struct DisplayCard: View {
    let display: DisplayBrightnessService.ManagedDisplay
    @ObservedObject var service: DisplayBrightnessService

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.s) {
                PocketIconTile(symbol: "display", tint: PocketTheme.brand, size: 28)
                Text(display.name).font(.title3.weight(.semibold))
                if display.active == .hardware {
                    PocketStatusBadge(text: "Donanım (DDC)", systemImage: "cpu", tone: .success)
                        .help("Monitörün kendi arka ışığı değişir.")
                } else {
                    PocketStatusBadge(text: "Yazılım", systemImage: "circle.lefthalf.filled", tone: .neutral)
                        .help("Görüntü karartılır; arka ışık aynı kalır.")
                }
                Spacer()
                Picker("Yöntem", selection: Binding(get: { service.settings.methods[display.key] ?? .automatic },
                                                    set: { service.settings.methods[display.key] = $0 })) {
                    Text("Otomatik").tag(DisplayBrightnessService.Method.automatic)
                    Text("Donanım (DDC)").tag(DisplayBrightnessService.Method.hardware)
                    Text("Yazılım").tag(DisplayBrightnessService.Method.software)
                }
                .labelsHidden()
                .fixedSize()
            }
            slider("Parlaklık", symbol: "sun.max", value: display.level) { service.setLevel($0, for: display.id) }
            if let contrast = display.contrast {
                slider("Kontrast", symbol: "circle.righthalf.filled", value: contrast) { service.setContrast($0, for: display.id) }
            }
            if !display.hardwareAvailable {
                Text("Bu monitör DDC/CI ile parlaklık bildirmedi. Monitörün kendi menüsünde DDC/CI açıksa “Donanım (DDC)” seçebilirsin; kapalıysa yazılımsal karartma kullanılır.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private func slider(_ title: LocalizedStringKey, symbol: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: PocketSpacing.m) {
            Label(title, systemImage: symbol).frame(width: 120, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: 0...1) { Text(title) }
                .labelsHidden()
            Text(verbatim: pocketPercent(value * 100)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
        }
    }
}
