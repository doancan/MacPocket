import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

/// Expands abbreviations as they are typed in any app. The tap only listens; the expansion is sent as
/// backspaces followed by the text, marked so no MacPocket tap reacts to it.
@MainActor
final class SnippetService: ObservableObject {
    static let shared = SnippetService()

    @Published var settings = SnippetSettings.load(from: .standard) {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: .standard)
            configureTap()
        }
    }
    @Published private(set) var tapActive = false
    @Published private(set) var expansions = 0

    private var matcher = SnippetMatcher()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private static let backspace: UInt16 = 51

    private init() {}

    func start() {
        configureTap()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.matcher.reset() }
        }
    }

    func configureTap() {
        let wanted = settings.enabled && AXIsProcessTrusted()
        if wanted && tap == nil {
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            let callback: CGEventTapCallBack = { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<SnippetService>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { service.handle(type, event) }
                return Unmanaged.passUnretained(event)
            }
            if let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                               eventsOfInterest: mask, callback: callback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) {
                let runLoopSource = CFMachPortCreateRunLoopSource(nil, created, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: created, enable: true)
                tap = created
                source = runLoopSource
            }
        } else if !wanted, let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            self.tap = nil
            source = nil
            matcher.reset()
        }
        tapActive = tap != nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown, .rightMouseDown:
            matcher.reset() // the caret probably moved
        case .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != MacroService.marker else { return }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == Self.backspace { matcher.deleteBackward(); return }
            if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty { matcher.reset(); return }
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
            guard length > 0, let character = String(utf16CodeUnits: buffer, count: length).first,
                  !character.isNewline, character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { matcher.reset(); return }
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, settings.excludedBundleIDs.contains(front) { return }
            guard let snippet = matcher.type(character, snippets: settings.snippets) else { return }
            expand(snippet)
        default:
            break
        }
    }

    private func expand(_ snippet: Snippet) {
        let text = SnippetExpander.expand(snippet.expansion, now: Date(), clipboard: NSPasteboard.general.string(forType: .string),
                                          locale: pocketLocale)
        // After the key that completed the abbreviation has reached the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            for _ in 0..<snippet.abbreviation.count { MacroRunner.post(KeyCombo(keyCode: Self.backspace, modifiers: [])) }
            MacroRunner.type(text)
        }
        expansions += 1
    }
}

/// Tools → Metin Kısaltmaları.
struct SnippetsView: View {
    @ObservedObject private var service = SnippetService.shared
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Metin Kısaltmaları",
                              subtitle: "Kısa bir kelime yaz, uzun metne dönüşsün: imza, adres, tarih, sık kullandığın cevaplar.",
                              icon: "text.badge.plus") {
                Toggle("Metin kısaltmaları", isOn: $service.settings.enabled).toggleStyle(.switch).labelsHidden()
            }
            if service.settings.enabled && !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Yazılanları izleyip genişletmek için Erişilebilirlik izni gerekir.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PocketSpacing.l) {
                    list
                    help
                }
                .padding(.bottom, PocketSpacing.l)
            }
        }
        .pocketPage()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private var list: some View {
        let duplicates = service.settings.duplicates
        return VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Kısaltmalar", icon: "list.bullet") {
                Button { service.settings.snippets.append(Snippet(abbreviation: ";yeni", expansion: "")) } label: {
                    Label("Ekle", systemImage: "plus")
                }
                .controlSize(.small)
            }
            ForEach($service.settings.snippets) { $snippet in
                HStack(alignment: .top, spacing: PocketSpacing.m) {
                    Toggle("Etkin", isOn: $snippet.enabled).toggleStyle(.checkbox).labelsHidden().padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Kısaltma", text: $snippet.abbreviation)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        if duplicates.contains(snippet.abbreviation) {
                            Text("Başka bir kısaltmayla aynı").font(.caption).foregroundStyle(.orange)
                        } else if !snippet.isValid {
                            Text("En az 2 karakter, boşluksuz; metin boş olamaz").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 6)
                    TextField("Genişleyecek metin", text: $snippet.expansion, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.roundedBorder)
                    Button { service.settings.snippets.removeAll { $0.id == snippet.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                        .accessibilityLabel("Kısaltmayı sil")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    /// Typed as localization keys so the descriptions are extracted and translated.
    private static let variables: [(String, LocalizedStringKey)] = [
        ("{date}", "Bugünün tarihi"), ("{time}", "Şu anki saat"), ("{datetime}", "Tarih ve saat"),
        ("{weekday}", "Haftanın günü"), ("{clipboard}", "Panodaki metin"),
    ]

    private var help: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.s) {
            PocketSectionHeader("Değişkenler", icon: "curlybraces")
            ForEach(Self.variables, id: \.0) { variable, meaning in
                HStack {
                    Text(verbatim: variable).font(.system(.callout, design: .monospaced)).frame(width: 110, alignment: .leading)
                    Text(meaning).foregroundStyle(.secondary)
                }
            }
            Text("İpucu: kısaltmaları “;” ile başlatmak, normal yazarken yanlışlıkla genişlemelerini önler. Parola alanlarında macOS tuşları iletmediği için kısaltmalar çalışmaz.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if service.expansions > 0 {
                Text("Bu oturumda \(service.expansions) kez genişletildi.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }
}
