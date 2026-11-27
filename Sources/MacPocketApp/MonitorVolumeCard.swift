import AppKit
import MacPocketCore
import SwiftUI

/// Ses Mikseri → monitor speaker: lets the volume keys drive a monitor's speakers over DDC when macOS can't.
struct MonitorVolumeCard: View {
    @ObservedObject private var service = MonitorVolumeService.shared
    @State private var trusted = AXIsProcessTrusted()
    @Environment(\.pocketTint) private var tint

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack(spacing: PocketSpacing.m) {
                PocketIconTile(symbol: "hifispeaker.fill", tint: tint, size: PocketIconSize.item)
                VStack(alignment: .leading, spacing: PocketSpacing.xxs) {
                    Text("Monitör hoparlörü").font(.headline)
                    Text("macOS’un sesini değiştiremediği HDMI ve DisplayPort monitörlerde ses tuşları monitörün kendi sesini ayarlar.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PocketSpacing.s)
                Toggle("Ses tuşları monitör hoparlörünü kontrol etsin", isOn: $service.settings.keysEnabled)
                    .pocketSwitch().labelsHidden()
                    .help("Ses tuşları monitör hoparlörünü kontrol etsin")
            }
            if service.settings.keysEnabled && !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Ses tuşlarını yakalamak için Erişilebilirlik izni gerekir. İzin verdikten sonra MacPocket’e dönmen yeterli.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            Divider()
            routeDetail
            Text("Gösterge, Ekran Parlaklığı’ndaki stil ve konum ayarını kullanır.")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
        .pocketCard()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    @ViewBuilder
    private var routeDetail: some View {
        switch service.route {
        case .monitor(let monitor):
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                HStack {
                    Label(monitor.name, systemImage: "display").font(.callout.weight(.semibold))
                    Spacer(minLength: PocketSpacing.s)
                    PocketStatusBadge(text: service.settings.keysEnabled && service.tapActive ? String(localized: "Tuşlar MacPocket’te") : String(localized: "Tuşlar kapalı"),
                                      systemImage: service.settings.keysEnabled && service.tapActive ? "keyboard.fill" : "keyboard",
                                      tone: service.settings.keysEnabled && service.tapActive ? .success : .neutral)
                }
                HStack(spacing: PocketSpacing.m) {
                    Button { service.toggleMute() } label: {
                        Image(systemName: BrightnessHUDSymbol.volume(muted: monitor.state.muted, level: monitor.state.level))
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(monitor.state.muted ? Text("Sesi aç") : Text("Sesi kapat"))
                    .accessibilityLabel(monitor.state.muted ? Text("Sesi aç") : Text("Sesi kapat"))
                    Slider(value: Binding(get: { monitor.state.level }, set: { service.setLevel($0) }), in: 0...1)
                        .tint(tint)
                        .accessibilityLabel(Text("\(monitor.name) ses seviyesi"))
                    Text(monitor.state.effectiveLevel, format: .percent.precision(.fractionLength(0)))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                if !monitor.nativeMute {
                    Text("Bu monitörün kendi sessiz komutu yok; sessiz tuşu sesi 0’a indirir ve tekrar basınca eski seviyeye döner.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .system(let name):
            Label("Şu anki ses çıkışı: \(name). Sesini macOS ayarlıyor; ses tuşları macOS’ta kalır.", systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(.secondary)
        case .unsupported(let name):
            Label("Şu anki ses çıkışı: \(name). Bu monitör sesi DDC ile değiştirmeye izin vermiyor.", systemImage: PocketTone.warning.symbol)
                .font(.callout).foregroundStyle(PocketTone.warning.color)
        case .none:
            Label(service.detecting ? "Ses çıkışı algılanıyor…" : "Ses çıkışı bulunamadı.", systemImage: "speaker.slash")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
