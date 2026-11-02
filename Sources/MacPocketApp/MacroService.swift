import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI

/// Runs keyboard macros. Triggers come from an event tap rather than global hotkeys so that a trigger with no
/// macro for the app in front passes through to that app untouched.
@MainActor
final class MacroService: ObservableObject {
    static let shared = MacroService()

    @Published var library = MacroLibrary() {
        didSet {
            guard library != oldValue else { return }
            save()
            configureTap()
        }
    }
    @Published private(set) var running: Macro.ID?
    @Published private(set) var lastError: String?
    @Published private(set) var recording = false
    @Published private(set) var recorded: [RecordedKey] = []
    @Published private(set) var tapActive = false
    @Published var launcherShortcut: KeyCombo? = MacroService.storedLauncherShortcut() {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(launcherShortcut), forKey: Self.launcherKey)
            registerLauncher()
        }
    }
    /// Suspends triggers while a shortcut is being recorded in the editor.
    var editingShortcut = false

    private let archive = MacroArchive.standard
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var runTask: Task<Void, Never>?
    private lazy var launcherHotKey = PocketGlobalHotKey { [weak self] in self?.launcher.toggle() }
    private lazy var launcher = MacroLauncherController(service: self)
    private let recordingHUD = MacroRecordingHUD()
    /// Marks events a macro posts so the tap never treats them as triggers or recorded input.
    nonisolated static let marker: Int64 = 0x4D50_4D43
    private static let launcherKey = "MacPocket.macros.launcher"
    private static let stopRecording = KeyCombo(keyCode: 53, modifiers: [.control, .option]) // ⌃⌥⎋

    private init() {}

    func start() {
        do { library = try archive.load() } catch { lastError = String(localized: "Makrolar okunamadı: \(error.localizedDescription)") }
        configureTap()
        registerLauncher()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureTap() }
        }
    }

    private static func storedLauncherShortcut() -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: launcherKey) else {
            return KeyCombo(keyCode: 49, modifiers: [.control, .option]) // ⌃⌥Space
        }
        return (try? JSONDecoder().decode(KeyCombo?.self, from: data)) ?? nil
    }

    private func registerLauncher() {
        if let launcherShortcut { launcherHotKey.register(launcherShortcut) } else { launcherHotKey.unregister() }
    }

    private func save() {
        do { try archive.save(library) } catch { lastError = String(localized: "Makrolar kaydedilemedi: \(error.localizedDescription)") }
    }

    func dismissError() { lastError = nil }

    // MARK: Tap

    func configureTap() {
        let wanted = (!library.triggers.isEmpty || recording) && AXIsProcessTrusted()
        if wanted && tap == nil {
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            let callback: CGEventTapCallBack = { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MacroService>.fromOpaque(context).takeUnretainedValue()
                let keep: Bool = MainActor.assumeIsolated { service.handle(type, event) }
                return keep ? Unmanaged.passUnretained(event) : nil
            }
            if let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: callback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) {
                let source = CFMachPortCreateRunLoopSource(nil, created, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: created, enable: true)
                tap = created
                tapSource = source
            }
        } else if !wanted, let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
            self.tap = nil
            tapSource = nil
        }
        tapActive = tap != nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard type == .keyDown, event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return true }
        let combo = Self.combo(of: event)
        if recording {
            if combo == Self.stopRecording { stopRecording(); return false }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                recorded.append(RecordedKey(keyCode: combo.keyCode, modifiers: combo.modifiers, characters: Self.characters(of: event),
                                            time: ProcessInfo.processInfo.systemUptime))
            }
            return true
        }
        guard !editingShortcut, running == nil,
              let macro = library.macro(for: combo, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return true }
        run(macro)
        return false
    }

    private static func combo(of event: CGEvent) -> KeyCombo {
        var modifiers: KeyCombo.Modifiers = []
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        return KeyCombo(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: modifiers)
    }

    private static func characters(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return length > 0 ? String(utf16CodeUnits: buffer, count: length) : nil
    }

    // MARK: Recording

    func startRecording() {
        guard AXIsProcessTrusted() else {
            lastError = String(localized: "Kayıt için MacPocket’e Erişilebilirlik izni ver.")
            return
        }
        recorded = []
        recording = true
        configureTap()
        recordingHUD.show(stop: { [weak self] in self?.stopRecording() })
    }

    func stopRecording() {
        recording = false
        recordingHUD.hide()
        configureTap()
    }

    // MARK: Running

    func run(_ macro: Macro) {
        guard running == nil else { return }
        if macro.needsReview == true {
            lastError = String(localized: "“\(macro.name)” içe aktarıldı; çalıştırmadan önce adımlarını inceleyip etkinleştir.")
            return
        }
        if let problem = macro.problems.first {
            lastError = String(localized: "“\(macro.name)” çalıştırılamadı: \(problem)")
            return
        }
        running = macro.id
        runTask = Task { [weak self] in
            for action in macro.plan {
                guard !Task.isCancelled else { break }
                do { try await MacroRunner.perform(action) } catch {
                    self?.lastError = String(localized: "“\(macro.name)” durdu: \(error.localizedDescription)")
                    break
                }
            }
            self?.running = nil
        }
    }

    func stop() { runTask?.cancel() }

    // MARK: Editing helpers

    func update(_ macro: Macro) {
        guard let index = library.macros.firstIndex(where: { $0.id == macro.id }) else { return }
        library.macros[index] = macro
    }

    func importMacros(from data: Data) throws -> Int {
        let macros = try MacroArchive.importing(data)
        library.macros.append(contentsOf: macros)
        return macros.count
    }

    func exportData(_ macros: [Macro]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(MacroLibrary(macros: macros))
    }
}

/// Carries out one step.
enum MacroRunner {
    enum Failure: LocalizedError {
        case applicationNotFound(String)
        case script(String)
        case process(String, Int32)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case let .applicationNotFound(id): String(localized: "Uygulama bulunamadı: \(id)")
            case let .script(message): String(localized: "AppleScript hatası: \(message)")
            case let .process(name, status): String(localized: "\(name) \(status) koduyla bitti")
            case let .timedOut(name): String(localized: "\(name) zaman aşımına uğradı")
            }
        }
    }

    @MainActor
    static func perform(_ action: MacroAction) async throws {
        switch action {
        case let .keystroke(combo):
            post(combo)
            try await Task.sleep(for: .milliseconds(30))
        case let .text(text):
            type(text)
            try await Task.sleep(for: .milliseconds(30))
        case let .delay(milliseconds):
            try await Task.sleep(for: .milliseconds(milliseconds))
        case let .openApplication(bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw Failure.applicationNotFound(bundleID)
            }
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case let .openURL(url):
            NSWorkspace.shared.open(url)
        case let .appleScript(source):
            // osascript, off the main thread and time-limited: an AppleScript waiting on a hung app must not
            // stall the main run loop, where every MacPocket event tap (and so the keyboard) is served.
            let result = try await BoundedProcess.run("/usr/bin/osascript", ["-e", source], timeout: MacroRunLimits.shellTimeout)
            if result.status != 0 { throw Failure.script(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case let .shortcut(name):
            try await runProcess("/usr/bin/shortcuts", ["run", name], label: String(localized: "Kestirme"))
        case let .shell(command):
            try await runProcess("/bin/zsh", ["-c", command], label: String(localized: "Komut"))
        }
    }

    static func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .combinedSessionState)
        var flags = CGEventFlags()
        if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if combo.modifiers.contains(.control) { flags.insert(.maskControl) }
        if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: MacroService.marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Types text in chunks of Unicode characters, independent of the keyboard layout. Also used by snippets.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            var end = min(index + 16, units.count)
            // Don't split a surrogate pair (emoji) across two events.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[index..<end])
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                // The trigger's ⌃⌥/⌘ may still be held: without clearing them the text would arrive as shortcuts.
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: MacroService.marker)
                event.post(tap: .cgSessionEventTap)
            }
            index = end
        }
    }

    private static func runProcess(_ path: String, _ arguments: [String], label: String) async throws {
        let result: BoundedProcess.Result
        do {
            result = try await BoundedProcess.run(path, arguments, timeout: MacroRunLimits.shellTimeout)
        } catch BoundedProcess.Failure.timedOut {
            throw Failure.timedOut(label)
        }
        guard result.status == 0 else { throw Failure.process(label, result.status) }
    }
}

// MARK: - Recording HUD

@MainActor
final class MacroRecordingHUD {
    private var panel: NSPanel?

    func show(stop: @escaping () -> Void) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: MacroRecordingHUDView(stop: stop))
        if let screen = NSScreen.main {
            let size = NSSize(width: 380, height: 64)
            panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct MacroRecordingHUDView: View {
    let stop: () -> Void
    @State private var pulse = false
    @PocketReduceMotion private var reduceMotion

    var body: some View {
        HStack(spacing: PocketSpacing.m) {
            Circle().fill(.red).frame(width: 12, height: 12)
                .opacity(pulse ? 0.35 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            Text("Kaydediliyor · durdurmak için ⌃⌥⎋").font(.callout.weight(.semibold))
            Spacer(minLength: 0)
            // Plain on the glass HUD: a glass button here would be glass on glass.
            Button("Durdur", action: stop).buttonStyle(.borderless).foregroundStyle(.red).font(.callout.weight(.semibold))
        }
        .padding(.horizontal, PocketSpacing.l)
        .frame(height: 52)
        .modifier(MacroHUDSurface())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MacroHUDSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .capsule)
    }
}
