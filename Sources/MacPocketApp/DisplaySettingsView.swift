import MacPocketCore
import SwiftUI

/// Tools → Ekran Ayarları: resolution (including hidden HiDPI modes), refresh rate, main display and mirroring.
struct DisplaySettingsView: View {
    @ObservedObject private var service = DisplaySettingsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekran Ayarları",
                              subtitle: "Çözünürlüğü, yenileme hızını ve ana ekranı değiştir; Sistem Ayarları’nın gizlediği keskin HiDPI modları dahil.",
                              icon: "display.2") {
                Button { service.refresh() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
            }
            if let failure = service.failure {
                HStack(alignment: .top) {
                    PocketMessage(failure, tone: .warning)
                    Button { service.dismissFailure() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        .accessibilityLabel("Mesajı kapat")
                }
            }
            if let pending = service.pending {
                HStack(spacing: PocketSpacing.m) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                    Text("\(pending.description) — \(service.remaining) sn içinde onaylamazsan eski ayara döner.").font(.callout)
                    Spacer()
                    Button("Geri Al") { service.revert() }
                    Button("Kalsın") { service.keep() }.buttonStyle(.pocketPrimary)
                }
                .pocketCard(padding: PocketSpacing.m)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    HStack(spacing: PocketSpacing.l) {
                        Toggle("Düşük çözünürlüklü modları da göster", isOn: $service.showLowResolution)
                        Spacer()
                        if service.displays.count > 1 {
                            Toggle("Ekranları yansıt", isOn: Binding(get: { service.isMirroring }, set: { service.setMirroring($0) }))
                                .disabled(service.pending != nil)
                        }
                    }
                    .toggleStyle(.switch)
                    ForEach(service.displays) { display in DisplaySettingsCard(display: display, service: service) }
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onAppear { service.refresh() }
    }
}

private struct DisplaySettingsCard: View {
    let display: DisplaySettingsService.Display
    @ObservedObject var service: DisplaySettingsService
    @Environment(\.pocketTint) private var tint
    /// The slider's position while dragging; applied when the drag ends.
    @State private var sliderIndex: Double?

    private var resolutions: [DisplayResolution] { service.resolutions(for: display) }
    private var currentIndex: Int? {
        resolutions.firstIndex { $0.width == display.current.width && $0.height == display.current.height && $0.isHiDPI == display.current.isHiDPI }
            ?? resolutions.firstIndex { abs($0.width - display.current.width) <= 1 && abs($0.height - display.current.height) <= 1 }
    }
    private var current: DisplayResolution? { currentIndex.map { resolutions[$0] } }
    private var recommended: DisplayResolution? { DisplayModeCatalog.recommended(resolutions, native: display.native) }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            header
            if display.mirroredFrom != nil {
                Label("Bu ekran ana ekranı yansıtıyor.", systemImage: "rectangle.on.rectangle").foregroundStyle(.secondary)
            } else {
                resolutionControl
                refreshControl
            }
        }
        .pocketCard()
        .disabled(service.pending != nil)
    }

    private var header: some View {
        HStack(spacing: PocketSpacing.m) {
            PocketIconTile(symbol: display.isBuiltin ? "laptopcomputer" : "display", tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PocketSpacing.xs) {
                    Text(verbatim: display.name).font(.headline)
                    if display.isMain { PocketStatusBadge(text: String(localized: "Ana ekran"), systemImage: "menubar.rectangle", tone: .success) }
                }
                Text(verbatim: DisplaySettingsService.describe(display.current)
                     + (display.native.map { " · " + String(localized: "panel \(String($0.width)) × \(String($0.height))") } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if !display.isMain, service.displays.count > 1 {
                Button("Ana Ekran Yap") { service.makeMain(display) }
                    .help("Menü çubuğu ve Dock bu ekrana taşınır")
            }
        }
    }

    @ViewBuilder
    private var resolutionControl: some View {
        if resolutions.count > 1 {
            VStack(alignment: .leading, spacing: PocketSpacing.s) {
                HStack {
                    Text("Çözünürlük").font(.callout.weight(.semibold))
                    Spacer()
                    Picker("Çözünürlük", selection: Binding(get: { current?.id ?? "" }, set: { id in
                        if let resolution = resolutions.first(where: { $0.id == id }) { choose(resolution) }
                    })) {
                        ForEach(resolutions) { resolution in
                            Text(label(resolution)).tag(resolution.id)
                        }
                        if current == nil { Text(verbatim: DisplaySettingsService.describe(display.current)).tag("") }
                    }
                    .labelsHidden()
                    .fixedSize()
                        .pocketMenuPicker()
                }
                Slider(value: Binding(get: { sliderIndex ?? Double(currentIndex ?? 0) }, set: { sliderIndex = $0.rounded() }),
                       in: 0...Double(max(1, resolutions.count - 1)), step: 1) {
                    Text("Çözünürlük")
                } minimumValueLabel: {
                    Text("Daha büyük metin").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Daha fazla alan").font(.caption).foregroundStyle(.secondary)
                } onEditingChanged: { editing in
                    guard !editing, let index = sliderIndex.map(Int.init), resolutions.indices.contains(index) else { return }
                    sliderIndex = nil
                    choose(resolutions[index])
                }
                .labelsHidden()
                if let index = sliderIndex.map(Int.init), resolutions.indices.contains(index) {
                    Text(label(resolutions[index])).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let recommended, recommended.id != current?.id {
                    Button { choose(recommended) } label: { Label("Önerilen: \(Self.size(recommended))", systemImage: "sparkles") }
                        .buttonStyle(.link)
                }
            }
        }
    }

    @ViewBuilder
    private var refreshControl: some View {
        if let current, current.refreshRates.count > 1 {
            HStack {
                Text("Yenileme hızı").font(.callout.weight(.semibold))
                Spacer()
                Picker("Yenileme hızı", selection: Binding(get: { display.current.roundedRefresh }, set: { rate in
                    if let mode = current.mode(refresh: rate) { service.apply(mode, to: display) }
                })) {
                    ForEach(current.refreshRates, id: \.self) { rate in Text("\(rate) Hz").tag(rate) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private static func size(_ resolution: DisplayResolution) -> String { "\(resolution.width) × \(resolution.height)" }

    private func label(_ resolution: DisplayResolution) -> String {
        var text = Self.size(resolution)
        if !resolution.isHiDPI { text += " " + String(localized: "(düşük çözünürlük)") }
        if resolution.id == recommended?.id { text += " — " + String(localized: "Önerilen") }
        return text
    }

    private func choose(_ resolution: DisplayResolution) {
        guard let mode = resolution.mode(refresh: display.current.roundedRefresh) else { return }
        service.apply(mode, to: display)
    }
}
