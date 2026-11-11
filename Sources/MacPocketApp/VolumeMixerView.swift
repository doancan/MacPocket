import AppKit
import MacPocketCore
import SwiftUI

/// Tools → Ses Mikseri.
struct VolumeMixerView: View {
    @ObservedObject private var modules = PocketModuleRuntime.shared
    private var service: VolumeMixerService
    private let showsMonitor: Bool

    init(service: VolumeMixerService = .shared, showsMonitor: Bool = true) {
        self.service = service; self.showsMonitor = showsMonitor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ses Mikseri",
                              subtitle: "Her uygulamanın ses düzeyini ve çıkış aygıtını ayrı seç; sesi %150’ye kadar yükselt.",
                              icon: "slider.vertical.3") {
                Button { service.refresh() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                    .disabled(service.refreshing)
            }
            if let failure = service.failure { PocketMessage(failure, tone: .warning) }
            ScrollView {
                if showsMonitor && modules.available.contains(.audioOutput) {
                    MonitorVolumeCard().padding(.bottom, PocketSpacing.m)
                }
                VStack(spacing: PocketSpacing.m) {
                    if service.apps.isEmpty {
                        if service.refreshing {
                            ProgressView("Ses uygulamaları okunuyor…").frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            ContentUnavailableView("Ses kullanan uygulama yok", systemImage: "speaker.slash",
                                                   description: Text("Bir uygulama ses çalmaya başlayınca burada görünür."))
                                .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                    ForEach(service.apps) { app in
                        MixerRow(app: app, service: service)
                        if app.id != service.apps.last?.id { Divider() }
                    }
                }
                .pocketCard()
                Text("Ses düzeyi veya çıkış tercihi değiştiğinde macOS sistem sesi izni isteyebilir. Ses bellekte işlenir; kaydedilmez. Seçili aygıt ayrılırsa sistem çıkışı kullanılır, yeniden bağlanınca tercih geri yüklenir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PocketSpacing.s)
            }
        }
        .pocketPage()
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { service.setViewVisible(true) }
        .onDisappear { service.setViewVisible(false) }
    }
}

private struct MixerRow: View {
    let app: AudioApp
    var service: VolumeMixerService

    var body: some View {
        let entry = service.settings.entry(for: app.id)
        let resolution = service.resolution(for: app.id)
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack(spacing: PocketSpacing.s) {
                PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID), size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: app.name).fontWeight(.medium).lineLimit(2)
                    Text(app.playing ? "Çalıyor" : "Sessiz").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Sıfırla") { service.reset(app.id) }
                    .buttonStyle(.borderless).font(.caption)
                    .help("Ses düzeyini ve çıkış tercihini sıfırla")
                    .disabled(entry.isNeutral)
            }
            HStack(spacing: PocketSpacing.m) {
                Button { service.toggleMute(for: app.id) } label: {
                    Image(systemName: entry.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(entry.muted ? "Sesi aç" : "Sessize al")
                .accessibilityIdentifier("mixer.mute." + app.id)
                Slider(value: Binding(get: { service.settings.entry(for: app.id).volume },
                                      set: { service.setVolume($0, for: app.id) }),
                       in: 0...VolumeMixerSettings.maximumVolume) { Text("Ses düzeyi") }
                    .labelsHidden().disabled(entry.muted)
                    .accessibilityLabel(Text("\(app.name) ses düzeyi"))
                    .accessibilityValue(Text(verbatim: pocketPercent(entry.volume * 100)))
                Text(verbatim: pocketPercent(entry.volume * 100)).monospacedDigit()
                    .foregroundStyle(entry.volume > 1 ? .orange : .secondary).frame(width: 58, alignment: .trailing)
            }
            Picker("Çıkış aygıtı", selection: Binding<String?>(get: { service.settings.entry(for: app.id).outputUID },
                                                              set: { service.setOutput($0, for: app.id) })) {
                Text("Sistem varsayılanı").tag(nil as String?)
                ForEach(service.devices) { device in Text(verbatim: device.name).tag(Optional(device.uid)) }
                if let uid = entry.outputUID, !service.devices.contains(where: { $0.uid == uid }) {
                    Text("\(entry.outputName ?? String(localized: "Seçilen aygıt")) (bağlı değil)").tag(Optional(uid))
                }
            }
            .frame(maxWidth: 440, alignment: .leading)
            .accessibilityLabel(Text("\(app.name) çıkış aygıtı"))
            .accessibilityIdentifier("mixer.output." + app.id)
                .pocketMenuPicker()
            status
            if resolution.preferredUnavailable {
                Label("Seçili aygıt bağlı değil. Sistem çıkışına geçilir; yeniden bağlanınca tercih geri yüklenir.", systemImage: "cable.connector.slash")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, PocketSpacing.xs)
    }

    @ViewBuilder private var status: some View {
        switch service.states[app.id] ?? .native {
        case .native:
            Label("Uygulamanın kendi ses yolu", systemImage: "speaker.wave.2").font(.caption).foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Ses yolu hazırlanıyor; izin penceresini kontrol et.").font(.caption).foregroundStyle(.secondary)
            }
        case .restoring:
            Label("Uygulamanın kendi ses yoluna dönülüyor…", systemImage: "arrow.uturn.backward")
                .font(.caption).foregroundStyle(.secondary)
        case .active:
            let output = service.devices.first { $0.uid == service.resolution(for: app.id).effectiveUID }?.name ?? String(localized: "Sistem varsayılanı")
            Label("Ses çıkışı: \(output)", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        case .noOutput:
            Label("Kullanılabilir ses çıkışı yok; uygulamanın kendi sesine dönüldü.", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Yönlendirme uygulanamadı; uygulamanın kendi sesine dönüldü.").font(.caption).foregroundStyle(.orange)
                Text(verbatim: message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Yeniden Dene") { service.retry(app.id) }.controlSize(.small)
            }
        }
    }
}
