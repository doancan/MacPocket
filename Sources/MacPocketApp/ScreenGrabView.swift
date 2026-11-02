import AppKit
import MacPocketCore
import SwiftUI

/// A short glass message near the top of the screen (functional layer over any app).
@MainActor
enum PocketToast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ text: String, symbol: String) {
        let panel = self.panel ?? {
            let created = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.isOpaque = false
            created.backgroundColor = .clear
            created.ignoresMouseEvents = true
            created.level = .statusBar
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return created
        }()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ToastView(text: text, symbol: symbol))
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let size = NSSize(width: 460, height: 64)
            panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private struct ToastView: View {
        let text: String
        let symbol: String

        var body: some View {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: symbol).font(.title3)
                Text(verbatim: text).font(.callout.weight(.semibold)).lineLimit(2)
            }
            .padding(.horizontal, PocketSpacing.l)
            .frame(minHeight: 48)
            .modifier(ToastSurface())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct ToastSurface: ViewModifier {
        @ViewBuilder
        func body(content: Content) -> some View {
            content.glassEffect(.regular, in: .capsule)
        }
    }
}

@MainActor
final class ScreenGrabService: ObservableObject {
    static let shared = ScreenGrabService()

    enum Action: String, CaseIterable, Codable { case text, code, color }

    struct Settings: Codable, Equatable {
        var shortcuts: [Action: KeyCombo] = [
            .text: KeyCombo(keyCode: 17, modifiers: [.control, .option, .shift]), // T
            .code: KeyCombo(keyCode: 12, modifiers: [.control, .option, .shift]), // Q
            .color: KeyCombo(keyCode: 8, modifiers: [.control, .option, .shift]), // C
        ]
        var colorFormat = PickedColor.Format.hex
        static let storageKey = "MacPocket.screenGrab.settings"
    }

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Settings.storageKey) }
            registerShortcuts()
        }
    }
    @Published private(set) var lastText = ""
    @Published private(set) var codes: [String] = []
    @Published private(set) var colors: [PickedColor] = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    var recordingShortcut = false { didSet { registerShortcuts() } }
    private var hotKeys: [Action: PocketGlobalHotKey] = [:]

    private init() {
        settings = UserDefaults.standard.data(forKey: Settings.storageKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    func start() { registerShortcuts() }

    private func registerShortcuts() {
        for action in Action.allCases {
            let hotKey = hotKeys[action] ?? PocketGlobalHotKey { [weak self] in self?.perform(action) }
            hotKeys[action] = hotKey
            if let combo = settings.shortcuts[action], !recordingShortcut { hotKey.register(combo) } else { hotKey.unregister() }
        }
    }

    func perform(_ action: Action) {
        switch action {
        case .text, .code: Task { await grab(action) }
        case .color: pickColor()
        }
    }

    /// Lets the user drag over an area with macOS's own capture UI, then reads it on the device.
    private func grab(_ action: Action) async {
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            message = String(localized: "Ekrandan okumak için MacPocket’e Ekran Kaydı izni ver; sonra tekrar dene.")
            return
        }
        busy = true
        defer { busy = false }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("macpocket-grab-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try? await BoundedProcess.run("/usr/sbin/screencapture", ["-i", "-x", file.path], timeout: 300)
        // Esc in the capture UI leaves no file: nothing to do.
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let result: Result<[String], Error> = await Task.detached {
            Result { action == .text ? [try ScreenTextReader.text(in: image)] : try ScreenTextReader.codes(in: image) }
        }.value
        switch result {
        case let .success(found):
            let text = found.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                PocketToast.show(action == .text ? String(localized: "Seçilen alanda metin bulunamadı") : String(localized: "Seçilen alanda kod bulunamadı"),
                                 symbol: "questionmark.circle")
                return
            }
            copy(text)
            if action == .text { lastText = text } else { codes = Array((found + codes).prefix(20)) }
            PocketToast.show(String(localized: "Panoya kopyalandı: \(String(text.prefix(60)))"), symbol: action == .text ? "text.viewfinder" : "qrcode.viewfinder")
        case let .failure(error):
            message = error.localizedDescription
        }
    }

    private func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let self, let rgb = color?.usingColorSpace(.sRGB) else { return }
            MainActor.assumeIsolated {
                let picked = PickedColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                self.colors = Array(([picked] + self.colors.filter { $0 != picked }).prefix(16))
                let text = picked.formatted(self.settings.colorFormat)
                self.copy(text)
                PocketToast.show(String(localized: "Panoya kopyalandı: \(text)"), symbol: "eyedropper")
            }
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func dismissMessage() { message = nil }
}

/// Tools → Ekrandan Al.
struct ScreenGrabView: View {
    @ObservedObject private var service = ScreenGrabService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Ekrandan Al",
                              subtitle: "Ekranın herhangi bir yerinden metni oku, QR kodunu çöz ya da rengi al; sonuç doğrudan panoya gelir. Her şey bu Mac’te işlenir.",
                              icon: "text.viewfinder")
            if let message = service.message {
                HStack(alignment: .top) {
                    PocketMessage(message, tone: .warning)
                    Button { service.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        .accessibilityLabel("Mesajı kapat")
                }
            }
            HStack(spacing: PocketSpacing.m) {
                actionTile(.text, title: "Metni oku", detail: "Bir alan seç; içindeki yazı Türkçe ve İngilizce tanınır.", symbol: "text.viewfinder",
                           tint: PocketTheme.brand)
                actionTile(.code, title: "QR kodunu oku", detail: "QR ve barkodların içeriğini çöz.", symbol: "qrcode.viewfinder",
                           tint: Color(hex: 0x7B5CFF))
                actionTile(.color, title: "Renk al", detail: "Büyüteçle bir piksel seç.", symbol: "eyedropper", tint: Color(hex: 0xE8458B))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    if !service.lastText.isEmpty {
                        VStack(alignment: .leading, spacing: PocketSpacing.s) {
                            PocketSectionHeader("Son okunan metin", icon: "text.alignleft") {
                                Button("Kopyala") { service.copy(service.lastText) }.controlSize(.small)
                            }
                            Text(verbatim: service.lastText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .pocketCard()
                    }
                    if !service.codes.isEmpty {
                        VStack(alignment: .leading, spacing: PocketSpacing.s) {
                            PocketSectionHeader("Okunan kodlar", icon: "qrcode")
                            ForEach(service.codes, id: \.self) { code in
                                HStack {
                                    Text(verbatim: code).textSelection(.enabled).lineLimit(2)
                                    Spacer()
                                    if let url = URL(string: code), url.scheme == "https" || url.scheme == "http" {
                                        Button("Aç") { NSWorkspace.shared.open(url) }.controlSize(.small)
                                    }
                                    Button("Kopyala") { service.copy(code) }.controlSize(.small)
                                }
                            }
                        }
                        .pocketCard()
                    }
                    colorsCard
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
    }

    private func actionTile(_ action: ScreenGrabService.Action, title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String,
                            tint: Color) -> some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            HStack {
                PocketIconTile(symbol: symbol, tint: tint, size: 32)
                Spacer()
                KeyComboRecorder(combo: Binding(get: { service.settings.shortcuts[action] }, set: { service.settings.shortcuts[action] = $0 }),
                                 allowsClearing: true, recording: { service.recordingShortcut = $0 })
            }
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            Button { service.perform(action) } label: { Text("Başlat").frame(maxWidth: .infinity) }
                .disabled(service.busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var colorsCard: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Renkler", icon: "paintpalette") {
                Picker("Kopyalanacak biçim", selection: $service.settings.colorFormat) {
                    Text("HEX").tag(PickedColor.Format.hex)
                    Text("RGB").tag(PickedColor.Format.rgb)
                    Text("HSL").tag(PickedColor.Format.hsl)
                    Text("SwiftUI").tag(PickedColor.Format.swiftUI)
                }
                .labelsHidden().fixedSize()
            }
            if service.colors.isEmpty {
                Text("Henüz renk alınmadı.").foregroundStyle(.secondary)
            }
            ForEach(Array(service.colors.enumerated()), id: \.offset) { _, color in
                HStack(spacing: PocketSpacing.m) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                        .frame(width: 28, height: 28)
                        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(PocketTheme.line) }
                    ForEach(PickedColor.Format.allCases, id: \.self) { format in
                        Button(color.formatted(format)) { service.copy(color.formatted(format)) }
                            .buttonStyle(.borderless)
                            .font(.system(.caption, design: .monospaced))
                            .help("Kopyala")
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}
