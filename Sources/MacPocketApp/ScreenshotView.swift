import AppKit
import ImageIO
import MacPocketCore
import SwiftUI

extension ScreenshotMode {
    var localizedTitle: String {
        switch self {
        case .allInOne: String(localized: "Hepsi bir arada")
        case .area: String(localized: "Alan")
        case .window: String(localized: "Pencere")
        case .fullscreen: String(localized: "Tam ekran")
        case .previousArea: String(localized: "Önceki alan")
        case .scrolling: String(localized: "Kaydırmalı")
        }
    }

    var symbol: String {
        switch self {
        case .allInOne: "camera.viewfinder"
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullscreen: "display"
        case .previousArea: "arrow.uturn.backward.square"
        case .scrolling: "rectangle.expand.vertical"
        }
    }
}

/// Tools → Ekran Görüntüsü: capture buttons with their shortcuts, after-capture and saving options, and the
/// history.
struct ScreenshotView: View {
    @ObservedObject private var service = ScreenshotService.shared
    @ObservedObject private var pins = ScreenshotService.shared.pins
    @State private var permission = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekran Görüntüsü",
                              subtitle: "Alan, pencere ya da tam ekran çek; köşedeki önizlemeden kopyala, kaydet, sürükle ya da işaretle.",
                              icon: "camera.viewfinder")
            if !permission {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Ekran görüntüsü için MacPocket’e Ekran Kaydı izni gerekir.", tone: .warning)
                    Button("İzin ver…") { CGRequestScreenCaptureAccess(); permission = CGPreflightScreenCaptureAccess() }
                }
            }
            if let message = service.message {
                HStack(alignment: .top) {
                    PocketMessage(message, tone: .warning)
                    Button { service.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        .accessibilityLabel("Mesajı kapat")
                }
            }
            if service.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Ekran görüntüsü işlemi sürüyor…").font(.callout)
                    Spacer()
                    Button("Çekimi İptal Et") { service.cancelCapture() }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    captureHero
                    HStack(alignment: .top, spacing: PocketSpacing.l) {
                        afterCaptureGroup
                        savingGroup
                    }
                    pinnedCaptures
                    historyCard
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission = CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: Capture

    private var captureHero: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: PocketSpacing.m)], spacing: PocketSpacing.m) {
                ForEach(ScreenshotMode.allCases, id: \.self) { mode in
                    CaptureModeTile(mode: mode, service: service)
                }
            }
            if let app = service.conflictingApp {
                ScreenshotNotice(symbol: PocketTone.warning.symbol,
                                 text: Text("\(app) açık: ⇧⌘3/4/5 gibi kısayollara o da yanıt verir. MacPocket’i kullanacaksan \(app)’in kısayollarını kapat ya da uygulamadan çık."))
            }
            if !service.failedShortcuts.isEmpty {
                ScreenshotNotice(symbol: PocketTone.warning.symbol,
                                 text: Text("Bazı kısayolları macOS’un kendi ekran görüntüsü kısayolları da kullanıyor. Sistem Ayarları → Klavye → Klavye Kısayolları → Ekran Resimleri’nden kapat ya da başka bir kısayol seç.")) {
                    Button("Klavye Kısayolları…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(PocketSpacing.l)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PocketTheme.panel)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(RadialGradient(colors: [Color.blue.opacity(0.13), .clear], center: .topLeading, startRadius: 0, endRadius: 420))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(RadialGradient(colors: [Color.purple.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(PocketTheme.line) }
    }

    // MARK: Settings

    private var afterCaptureGroup: some View {
        SettingsGroup(title: "Çekimden sonra") {
            SettingsRow(symbol: "doc.on.doc.fill", color: .blue, title: "Panoya kopyala") {
                Toggle("Panoya kopyala", isOn: $service.settings.copyToClipboard).labelsHidden()
            }
            SettingsRow(symbol: "square.and.arrow.down.fill", color: .green, title: "Klasöre kaydet") {
                Toggle("Klasöre kaydet", isOn: $service.settings.saveToFolder).labelsHidden()
            }
            SettingsRow(symbol: "rectangle.inset.bottomleft.filled", color: .purple, title: "Köşede önizleme göster") {
                Toggle("Köşede önizleme göster", isOn: $service.settings.showOverlay).labelsHidden()
            }
            SettingsRow(symbol: "hand.draw.fill", color: .orange, title: "Sürükleyince önizlemeyi kapat") {
                Toggle("Sürükleyince önizlemeyi kapat", isOn: $service.settings.closeOverlayAfterDrag).labelsHidden()
            }
            .disabled(!service.settings.showOverlay)
            SettingsRow(symbol: "timer", color: .gray, title: "Önizleme kendiliğinden kapansın") {
                Picker("Önizleme kendiliğinden kapansın", selection: $service.settings.overlayAutoClose) {
                    Text("Hayır").tag(Int?.none)
                    ForEach([5, 10, 30], id: \.self) { seconds in Text("\(seconds) sn sonra").tag(Int?.some(seconds)) }
                }
                .labelsHidden().fixedSize()
                    .pocketMenuPicker()
            }
            .disabled(!service.settings.showOverlay)
            SettingsRow(symbol: "speaker.wave.2.fill", color: .red, title: "Deklanşör sesi") {
                Toggle("Deklanşör sesi", isOn: $service.settings.playSound).labelsHidden()
            }
        }
    }

    private var savingGroup: some View {
        SettingsGroup(title: "Kaydetme") {
            SettingsRow(symbol: "photo.fill", color: .indigo, title: "Biçim") {
                Picker("Biçim", selection: $service.settings.format) {
                    Text(verbatim: "PNG").tag(ScreenshotFormat.png)
                    Text(verbatim: "JPG").tag(ScreenshotFormat.jpg)
                    Text(verbatim: "HEIC").tag(ScreenshotFormat.heic)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if service.settings.format != .png {
                SettingsRow(symbol: "dial.medium.fill", color: .teal, title: "Kalite") {
                    HStack {
                        Slider(value: $service.settings.quality, in: 0.5...1).frame(width: 120)
                        Text(service.settings.quality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
            }
            SettingsRow(symbol: "folder.fill", color: .blue, title: "Klasör",
                        detail: service.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                HStack(spacing: PocketSpacing.xs) {
                    Button("Değiştir…") { chooseFolder() }
                    Button { NSWorkspace.shared.open(service.folder) } label: { Image(systemName: "arrow.up.forward.app") }
                        .help("Klasörü aç")
                        .accessibilityLabel("Klasörü aç")
                }
            }
            Text("Saydam pencere gölgeleri PNG ve HEIC’te korunur; JPG’de beyaz zemine basılır.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PocketSpacing.m).padding(.vertical, PocketSpacing.s)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = service.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        service.settings.folder = url.path
    }

    // MARK: History

    private var pinnedCaptures: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Ekranda Sabitlenenler", icon: "pin")
            Text("Önizlemedeki Sabitle düğmesinden veya geçmişteki menüden görüntüyü sabitle. Sabit görüntüler bu oturumda bellekte tutulur; modül kapanınca kapanır.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let capture = service.latestCapture {
                Button("Son Çekimi Sabitle") { service.pin(capture) }.disabled(service.busy)
            }
            ForEach(pins.items) { model in
                HStack {
                    Text(verbatim: "\(model.capture.image.width) × \(model.capture.image.height)").monospacedDigit()
                    Spacer()
                    Button("Göster") { pins.show(model.id) }
                    Button("Kapat") { pins.close(model.id) }
                }
            }
            if !pins.items.isEmpty { Button("Tüm Sabitlemeleri Kapat") { pins.closeAll() } }
        }.frame(maxWidth: .infinity, alignment: .leading).pocketCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            HStack {
                Text("Geçmiş").font(.headline)
                Spacer()
                Text("Son 30 gün · \(service.history.entries.count) çekim").font(.subheadline).foregroundStyle(.secondary)
            }
            if service.history.entries.isEmpty {
                VStack(spacing: PocketSpacing.s) {
                    Image(systemName: "photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Henüz kaydedilmiş ekran görüntüsü yok.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: PocketSpacing.m)], spacing: PocketSpacing.m) {
                    ForEach(service.history.entries) { entry in HistoryTile(entry: entry) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}

// MARK: - Capture tile

private struct CaptureModeTile: View {
    let mode: ScreenshotMode
    @ObservedObject var service: ScreenshotService
    @Environment(\.pocketTint) private var tint
    @State private var hovering = false
    @State private var editingShortcut = false

    private var primary: Bool { mode == .allInOne }

    var body: some View {
        VStack(spacing: PocketSpacing.s) {
            Button { service.capture(mode) } label: {
                VStack(spacing: PocketSpacing.s) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(primary ? Color.accentColor : .primary)
                        .frame(width: 48, height: 48)
                        .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    Text(mode.localizedTitle).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(service.busy)
            .help(Text("\(mode.localizedTitle) çek"))
            Button { editingShortcut = true } label: { ShortcutCaps(combo: service.settings.shortcuts[mode], conflict: service.failedShortcuts.contains(mode)) }
                .buttonStyle(.plain)
                .help("Kısayolu değiştir")
                .popover(isPresented: $editingShortcut, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: PocketSpacing.s) {
                        Text("\(mode.localizedTitle) kısayolu").font(.headline)
                        KeyComboRecorder(combo: Binding(get: { service.settings.shortcuts[mode] }, set: { service.settings.shortcuts[mode] = $0 }),
                                         allowsClearing: true, recording: { service.recordingShortcut = $0 })
                        Text("Tıkla ve yeni kısayola bas; kapatmak için kayıt sırasında ⌫.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(PocketSpacing.m)
                    .frame(width: 260)
                }
        }
        .padding(.vertical, PocketSpacing.m)
        .padding(.horizontal, PocketSpacing.s)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(primary ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.primary.opacity(hovering ? 0.08 : 0.045)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(primary ? Color.accentColor.opacity(0.35) : PocketTheme.line)
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// A shortcut drawn as keyboard keys, or "Kısayol ekle" when none is set.
private struct ShortcutCaps: View {
    let combo: KeyCombo?
    var conflict = false

    var body: some View {
        HStack(spacing: 3) {
            if let combo {
                ForEach(Array(Self.caps(combo.displayName).enumerated()), id: \.offset) { _, cap in
                    Text(verbatim: cap).font(.system(size: 11, weight: .semibold)).frame(minWidth: 16).padding(.horizontal, 4).padding(.vertical, 2)
                        .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(PocketTheme.line) }
                        .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
                }
            } else {
                Text("Kısayol ekle").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(PocketTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3])) }
            }
            if conflict {
                Image(systemName: PocketTone.warning.symbol).font(.caption).foregroundStyle(PocketTone.warning.color)
            }
        }
        .foregroundStyle(.secondary)
    }

    /// "⇧⌘5" → ["⇧", "⌘", "5"]: each modifier its own key, the rest as one.
    static func caps(_ name: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var caps = name.filter { modifiers.contains($0) }.map(String.init)
        let key = String(name.filter { !modifiers.contains($0) })
        if !key.isEmpty { caps.append(key) }
        return caps
    }
}

private struct ScreenshotNotice<Accessory: View>: View {
    let symbol: String
    let text: Text
    @ViewBuilder var accessory: () -> Accessory

    init(symbol: String, text: Text, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.symbol = symbol
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PocketSpacing.s) {
            Image(systemName: symbol).foregroundStyle(PocketTone.warning.color)
            text.font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PocketSpacing.s)
            accessory()
        }
        .padding(.horizontal, PocketSpacing.m).padding(.vertical, PocketSpacing.s)
        .background(PocketTone.warning.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Settings rows (System Settings style)

private struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.xs) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, PocketSpacing.xs)
            VStack(spacing: 0) {
                Group(subviews: content()) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        if index > 0 { Divider().padding(.leading, 46) }
                        subview
                    }
                }
            }
            .background(PocketTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PocketTheme.line) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    var detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer(minLength: PocketSpacing.s)
            accessory().pocketSwitch()
        }
        .padding(.horizontal, PocketSpacing.m)
        .padding(.vertical, 7)
    }
}

// MARK: - History

private struct HistoryTile: View {
    let entry: ScreenshotHistoryEntry
    @State private var thumbnail: NSImage?
    @State private var hovering = false
    @State private var outputTask: Task<Void, Never>?
    @State private var outputBusy = false

    var body: some View {
        Color.clear
            .aspectRatio(16 / 11, contentMode: .fit)
            .background(.quaternary)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold))
                        Text(verbatim: "\(entry.pixelWidth) × \(entry.pixelHeight) · \(entry.mode.localizedTitle)").font(.caption2).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(8)
                }
                .frame(height: 52)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 5) {
                        tileButton("pencil", help: "Düzenle") { edit() }
                        tileButton("doc.on.doc", help: "Kopyala") { copy() }
                        Menu {
                            Button("Aç") { NSWorkspace.shared.open(URL(fileURLWithPath: entry.path)) }
                            Button("Finder’da Göster") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                            Divider()
                            Button("Ekranda sabitle") { pin() }.disabled(ScreenshotService.shared.busy)
                            Button("Geçmişten Kaldır") { ScreenshotService.shared.removeFromHistory(entry.id) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(.black.opacity(0.55), in: Circle())
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    }
                    .padding(6)
                    .disabled(outputBusy)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(PocketTheme.line) }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onTapGesture(count: 2) { edit() }
        .task(id: entry.path) { thumbnail = await Self.loadThumbnail(entry.path) }
        .onDisappear { outputTask?.cancel() }
        .overlay { if outputBusy { ProgressView().padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) } }
        .help(entry.path)
    }

    private func tileButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func edit() {
        perform { capture in ScreenshotEditor.open(capture) }
    }
    private func pin() {
        perform { capture in _ = ScreenshotService.shared.pin(capture) }
    }

    private func copy() {
        perform { capture in
            let data = try await ScreenshotAsyncOutput.encode(capture.image, format: .png, quality: 1, scale: Double(capture.scale))
            try Task.checkCancellation()
            guard ScreenshotService.shared.moduleRunning else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            PocketToast.show(String(localized: "Panoya kopyalandı"), symbol: "doc.on.doc")
        }
    }

    private func perform(_ operation: @escaping @MainActor (ScreenshotCapture) async throws -> Void) {
        guard !outputBusy, ScreenshotService.shared.moduleRunning, !ScreenshotService.shared.busy else { return }
        outputBusy = true
        let entry = entry
        outputTask = Task {
            defer { outputBusy = false; outputTask = nil }
            do {
                let capture = try await ScreenshotAsyncOutput.load(entry)
                try Task.checkCancellation()
                guard ScreenshotService.shared.moduleRunning else { return }
                try await operation(capture)
            } catch is CancellationError {} catch {
                PocketToast.show(String(localized: "Görüntü dışa aktarılamadı: \(error.localizedDescription)"), symbol: "exclamationmark.triangle")
            }
        }
    }

    private static func loadThumbnail(_ path: String) async -> NSImage? {
        await Task.detached {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                              kCGImageSourceThumbnailMaxPixelSize: 480,
                                                                              kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }
}
