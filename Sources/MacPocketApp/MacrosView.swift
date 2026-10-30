import AppKit
import ApplicationServices
import MacPocketCore
import SwiftUI
import UniformTypeIdentifiers

/// Tools → Makrolar: keyboard macros with per-app triggers, recording and a launcher.
struct MacrosView: View {
    @ObservedObject private var service = MacroService.shared
    @State private var selection: Macro.ID?
    @State private var trusted = AXIsProcessTrusted()
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.l) {
            PocketPageHeading(title: "Makrolar",
                              subtitle: "Tekrarlanan işleri adımlara dök, bir kısayola bağla: tuş basma, metin yazma, uygulama açma, AppleScript, Kestirmeler ve komutlar.",
                              icon: "wand.and.stars") {
                HStack(spacing: PocketSpacing.s) {
                    Menu {
                        Button("İçe aktar…", action: importMacros)
                        Button("Tümünü dışa aktar…") { export(service.library.macros) }.disabled(service.library.macros.isEmpty)
                    } label: { Label("Paylaş", systemImage: "square.and.arrow.up.on.square") }
                    .fixedSize()
                    Button { add() } label: { Label("Yeni makro", systemImage: "plus") }
                        .buttonStyle(.pocketPrimary)
                }
            }
            if !trusted {
                HStack(spacing: PocketSpacing.m) {
                    PocketMessage("Makrolar tuş basabilmek ve kısayolları yakalayabilmek için Erişilebilirlik izni ister.", tone: .warning)
                    Button("İzin ver…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            if let error = service.lastError {
                HStack(alignment: .top) {
                    PocketMessage(error, tone: .warning)
                    Button { service.dismissError() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        .accessibilityLabel("Uyarıyı kapat")
                }
            }
            if let message { PocketMessage(message, tone: .success) }
            HStack(alignment: .top, spacing: PocketSpacing.l) {
                list.frame(width: 280)
                if let index = service.library.macros.firstIndex(where: { $0.id == selection }) {
                    MacroEditor(macro: $service.library.macros[index], service: service, conflict: service.library.conflicts.contains(selection!),
                                export: { export([service.library.macros[index]]) },
                                delete: { delete(service.library.macros[index].id) })
                        .id(selection)
                } else {
                    ContentUnavailableView("Bir makro seç", systemImage: "wand.and.stars",
                                           description: Text("Soldan bir makro seç ya da yenisini oluştur."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .pocketCard()
                }
            }
        }
        .pocketPage()
        .onAppear { if selection == nil { selection = service.library.macros.first?.id } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.library.macros.isEmpty {
                Text("Henüz makro yok.").foregroundStyle(.secondary).padding(PocketSpacing.l)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(service.library.macros) { macro in
                        MacroRow(macro: macro, selected: selection == macro.id, running: service.running == macro.id,
                                 conflict: service.library.conflicts.contains(macro.id))
                            .contentShape(Rectangle())
                            .onTapGesture { selection = macro.id }
                    }
                }
                .padding(PocketSpacing.s)
            }
            Divider()
            HStack {
                Text("Başlatıcı").font(.callout)
                Spacer()
                KeyComboRecorder(combo: $service.launcherShortcut, allowsClearing: true, recording: { service.editingShortcut = $0 })
            }
            .padding(PocketSpacing.m)
            .help("Makroları adıyla arayıp çalıştıran paneli açar.")
        }
        .frame(maxHeight: .infinity)
        .pocketCard(padding: 0)
    }

    private func add() {
        let macro = Macro(name: String(localized: "Yeni makro"), steps: [MacroStep(.template(.text))])
        service.library.macros.append(macro)
        selection = macro.id
    }

    private func delete(_ id: Macro.ID) {
        service.library.macros.removeAll { $0.id == id }
        selection = service.library.macros.first?.id
    }

    private func export(_ macros: [Macro]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = macros.count == 1 ? "\(macros[0].name).json" : "MacPocket Makrolar.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.exportData(macros).write(to: url, options: .atomic)
            message = String(localized: "\(macros.count) makro dışa aktarıldı.")
        } catch {
            message = nil
            service.dismissError()
        }
    }

    private func importMacros() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try service.importMacros(from: Data(contentsOf: url))
            message = String(localized: "\(count) makro içe aktarıldı. Kısayolları kontrol et.")
        } catch {
            message = String(localized: "Dosya okunamadı: \(error.localizedDescription)")
        }
    }
}

private struct MacroRow: View {
    let macro: Macro
    let selected: Bool
    let running: Bool
    let conflict: Bool

    var body: some View {
        HStack(spacing: PocketSpacing.s) {
            Image(systemName: running ? "play.circle.fill" : macro.symbol)
                .foregroundStyle(macro.enabled ? Color.accentColor : .secondary)
                .frame(width: 22)
                .symbolEffect(.pulse, isActive: running)
            VStack(alignment: .leading, spacing: 1) {
                Text(macro.name).lineLimit(1).foregroundStyle(macro.enabled ? .primary : .secondary)
                HStack(spacing: PocketSpacing.xs) {
                    Text(macro.trigger?.displayName ?? String(localized: "Kısayol yok")).monospaced()
                    if !macro.isGlobal { Image(systemName: "app.badge").accessibilityLabel("Uygulamaya özel") }
                    if conflict { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Çakışıyor") }
                    if macro.needsReview == true { Text("İncele").foregroundStyle(.orange).fontWeight(.semibold) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PocketSpacing.s).padding(.vertical, PocketSpacing.xs + 2)
        .background(selected ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Editor

private struct MacroEditor: View {
    @Binding var macro: Macro
    @ObservedObject var service: MacroService
    let conflict: Bool
    let export: () -> Void
    let delete: () -> Void
    @State private var confirmDelete = false
    @State private var reviewing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSpacing.l) {
                header
                trigger
                steps
            }
            .padding(.bottom, PocketSpacing.l)
        }
        .onChange(of: service.recording) { _, isRecording in
            guard !isRecording, !service.recorded.isEmpty else { return }
            macro.steps += MacroRecorder.steps(from: service.recorded).map { MacroStep($0) }
        }
    }

    private var header: some View {
        HStack(spacing: PocketSpacing.m) {
            TextField("Makro adı", text: $macro.name).textFieldStyle(.plain).font(.title2.weight(.semibold))
            Toggle("Etkin", isOn: Binding(get: { macro.enabled }, set: { isOn in
                // Imported macros are reviewed once before they may run.
                if isOn && macro.needsReview == true { reviewing = true } else { macro.enabled = isOn }
            }))
            .toggleStyle(.switch).labelsHidden().help("Makroyu aç veya kapat")
            .confirmationDialog("İçe aktarılan makro etkinleştirilsin mi?", isPresented: $reviewing) {
                Button("İnceledim, etkinleştir") {
                    macro.needsReview = nil
                    macro.enabled = true
                }
            } message: {
                Text(reviewMessage)
            }
            if service.running == macro.id {
                Button("Durdur") { service.stop() }
            } else {
                Button { service.run(macro) } label: { Label("Çalıştır", systemImage: "play.fill") }
                    .buttonStyle(.pocketPrimary)
                    .disabled(macro.steps.isEmpty)
            }
            Menu {
                Button("Dışa aktar…", action: export)
                Divider()
                Button("Sil…", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .confirmationDialog("“\(macro.name)” silinsin mi?", isPresented: $confirmDelete) {
                Button("Sil", role: .destructive, action: delete)
            }
        }
        .pocketCard()
    }

    private var trigger: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Tetikleyici", icon: "keyboard")
            HStack(spacing: PocketSpacing.m) {
                Text("Kısayol")
                KeyComboRecorder(combo: $macro.trigger, allowsClearing: true, recording: { service.editingShortcut = $0 })
                if conflict {
                    PocketStatusBadge(text: "Çakışıyor", systemImage: "exclamationmark.triangle", tone: .warning)
                        .help("Aynı kısayol aynı kapsamda başka bir makroda da var; yalnız ilki çalışır.")
                }
                Spacer()
                Stepper(value: $macro.repeatCount, in: MacroRunLimits.repeatRange) {
                    Text("\(macro.repeatCount) kez çalıştır").monospacedDigit()
                }
                .fixedSize()
            }
            Picker("Nerede çalışsın", selection: Binding(get: { macro.applications.isEmpty ? 0 : 1 },
                                                         set: { if $0 == 0 { macro.applications = [] } else if macro.applications.isEmpty { addApplications() } })) {
                Text("Her uygulamada").tag(0)
                Text("Yalnız seçili uygulamalarda").tag(1)
            }
            .pickerStyle(.radioGroup)
            if !macro.applications.isEmpty {
                ForEach(macro.applications, id: \.self) { bundleID in
                    HStack(spacing: PocketSpacing.s) {
                        PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), size: 18)
                        Text(Self.applicationName(bundleID))
                        Spacer()
                        Button { macro.applications.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(Self.applicationName(bundleID)) uygulamasını çıkar")
                    }
                }
                Button { addApplications() } label: { Label("Uygulama ekle…", systemImage: "plus") }
                Text("Aynı kısayol başka uygulamalarda başka bir makroyu çalıştırabilir; makrosu olmayan uygulamada tuş olduğu gibi uygulamaya gider.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: PocketSpacing.m) {
            PocketSectionHeader("Adımlar", icon: "list.number") {
                HStack(spacing: PocketSpacing.s) {
                    Button { service.recording ? service.stopRecording() : service.startRecording() } label: {
                        Label(service.recording ? "Kaydı durdur" : "Kaydet", systemImage: service.recording ? "stop.circle.fill" : "record.circle")
                    }
                    .foregroundStyle(service.recording ? .red : .primary)
                    .help("Yazdıklarını ve bastığın kısayolları adımlara çevirir; ⌃⌥⎋ ile durur.")
                    Menu {
                        ForEach(MacroAction.Kind.allCases, id: \.self) { kind in
                            Button { macro.steps.append(MacroStep(.template(kind))) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: { Label("Adım ekle", systemImage: "plus") }
                    .fixedSize()
                }
                .controlSize(.small)
            }
            if macro.steps.isEmpty {
                Text("Adım ekle ya da kaydet.").foregroundStyle(.secondary)
            }
            ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                MacroStepRow(number: index + 1, action: $macro.steps[index].action, service: service,
                             moveUp: index > 0 ? { macro.steps.swapAt(index, index - 1) } : nil,
                             moveDown: index < macro.steps.count - 1 ? { macro.steps.swapAt(index, index + 1) } : nil,
                             remove: { macro.steps.removeAll { $0.id == step.id } })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketCard()
    }

    /// Lists every step that runs code or opens something, so enabling an imported macro is an informed choice.
    private var reviewMessage: String {
        let sensitive = macro.sensitiveSteps.map { action -> String in
            switch action {
            case let .shell(command): String(localized: "Komut: \(command)")
            case let .appleScript(source): String(localized: "AppleScript: \(String(source.prefix(120)))")
            case let .openURL(url): String(localized: "Açılacak: \(url.absoluteString)")
            case let .shortcut(name): String(localized: "Kestirme: \(name)")
            default: ""
            }
        }
        guard !sensitive.isEmpty else { return String(localized: "Bu makro kod çalıştıran bir adım içermiyor.") }
        return String(localized: "Bu makro şunları çalıştıracak:") + "\n" + sensitive.joined(separator: "\n")
    }

    static func applicationName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !macro.applications.contains($0) }
        macro.applications.append(contentsOf: ids)
    }
}

private struct MacroStepRow: View {
    let number: Int
    @Binding var action: MacroAction
    @ObservedObject var service: MacroService
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let remove: () -> Void
    @State private var urlText = ""
    @State private var shortcuts: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: PocketSpacing.m) {
            Text("\(number)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 18, alignment: .trailing)
                .padding(.top, 6)
            PocketIconTile(symbol: action.kind.symbol, tint: action.kind.tint, size: 26)
            VStack(alignment: .leading, spacing: PocketSpacing.xs) {
                Text(action.kind.title).font(.callout.weight(.semibold))
                editor
                if let problem = action.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: PocketSpacing.s)
            HStack(spacing: 2) {
                Button { moveUp?() } label: { Image(systemName: "chevron.up") }.disabled(moveUp == nil).accessibilityLabel("Yukarı taşı")
                Button { moveDown?() } label: { Image(systemName: "chevron.down") }.disabled(moveDown == nil).accessibilityLabel("Aşağı taşı")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.accessibilityLabel("Adımı sil")
            }
            .buttonStyle(.borderless)
        }
        .padding(PocketSpacing.s)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: PocketRadius.medium, style: .continuous))
    }

    @ViewBuilder private var editor: some View {
        switch action {
        case let .keystroke(combo):
            KeyComboRecorder(combo: Binding(get: { combo }, set: { if let value = $0 { action = .keystroke(value) } }),
                             requiresModifier: false, recording: { service.editingShortcut = $0 })
        case let .text(text):
            TextField("Yazılacak metin", text: Binding(get: { text }, set: { action = .text($0) }), axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
        case let .delay(milliseconds):
            HStack {
                TextField("ms", value: Binding(get: { milliseconds }, set: { action = .delay(milliseconds: $0) }), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                Text("ms").foregroundStyle(.secondary)
            }
        case let .openApplication(bundleID):
            HStack {
                PocketAppIcon(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), size: 20)
                Text(MacroEditor.applicationName(bundleID))
                Button("Değiştir…") { chooseApplication() }.controlSize(.small)
            }
        case let .openURL(url):
            TextField("https://… veya dosya yolu", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onAppear { urlText = url.isFileURL ? url.path : url.absoluteString }
                .onSubmit(saveURL)
                .onChange(of: urlText) { _, _ in saveURL() }
        case let .appleScript(source):
            TextEditor(text: Binding(get: { source }, set: { action = .appleScript($0) }))
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(PocketTheme.sidebar, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case let .shortcut(name):
            HStack {
                TextField("Kestirme adı", text: Binding(get: { name }, set: { action = .shortcut(name: $0) }))
                    .textFieldStyle(.roundedBorder)
                if !shortcuts.isEmpty {
                    Menu("Seç") { ForEach(shortcuts, id: \.self) { item in Button(item) { action = .shortcut(name: item) } } }
                        .fixedSize()
                }
            }
            .task { shortcuts = await Self.loadShortcuts() }
        case let .shell(command):
            VStack(alignment: .leading, spacing: 2) {
                TextField("Komut", text: Binding(get: { command }, set: { action = .shell(command: $0) }))
                    .font(.system(.callout, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Text("zsh ile, senin kullanıcınla çalışır; 30 saniyede bitmezse durdurulur.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            action = .openURL(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
        } else if let url = URL(string: trimmed), url.scheme != nil {
            action = .openURL(url)
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let id = panel.url.flatMap({ Bundle(url: $0)?.bundleIdentifier }) else { return }
        action = .openApplication(bundleID: id)
    }

    /// The user's Apple Shortcuts, from `shortcuts list`.
    private static func loadShortcuts() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).sorted()
        }.value
    }
}

extension MacroAction.Kind {
    var title: String {
        switch self {
        case .keystroke: String(localized: "Kısayola bas")
        case .text: String(localized: "Metin yaz")
        case .delay: String(localized: "Bekle")
        case .openApplication: String(localized: "Uygulama aç")
        case .openURL: String(localized: "Adres veya dosya aç")
        case .appleScript: String(localized: "AppleScript çalıştır")
        case .shortcut: String(localized: "Kestirme çalıştır")
        case .shell: String(localized: "Komut çalıştır")
        }
    }

    var symbol: String {
        switch self {
        case .keystroke: "command"
        case .text: "character.cursor.ibeam"
        case .delay: "hourglass"
        case .openApplication: "app.badge"
        case .openURL: "link"
        case .appleScript: "applescript"
        case .shortcut: "square.2.layers.3d"
        case .shell: "terminal"
        }
    }

    var tint: Color {
        switch self {
        case .keystroke: PocketTheme.brand
        case .text: Color(hex: 0x7B5CFF)
        case .delay: Color(hex: 0x8E8E93)
        case .openApplication: PocketTheme.disk
        case .openURL: Color(hex: 0x00A6C8)
        case .appleScript: Color(hex: 0x5F6B7E)
        case .shortcut: Color(hex: 0xE8458B)
        case .shell: Color(hex: 0x2C2C34)
        }
    }
}

// MARK: - Launcher

/// A floating, non-activating search panel that runs a macro by name in the app in front.
@MainActor
final class MacroLauncherController {
    private unowned let service: MacroService
    private var panel: LauncherPanel?
    private var keyMonitor: Any?
    private let state = LauncherState()

    init(service: MacroService) { self.service = service }

    func toggle() { panel?.isVisible == true ? close() : show() }

    private func show() {
        state.query = ""
        state.selected = 0
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let size = NSSize(width: 520, height: 340)
            panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.62 - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let used: Bool = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return used ? nil : event
        }
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
    }

    private var results: [Macro] { service.library.search(state.query) }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        switch event.keyCode {
        case 53: close(); return true
        case 125: state.selected = min(state.selected + 1, max(0, results.count - 1)); return true
        case 126: state.selected = max(0, state.selected - 1); return true
        case 36, 76:
            let list = results
            guard list.indices.contains(state.selected) else { return true }
            let macro = list[state.selected]
            close()
            // Give focus back to the app in front before the first keystroke.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.service.run(macro) }
            return true
        default:
            return false
        }
    }

    private func makePanel() -> LauncherPanel {
        let panel = LauncherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.onResign = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: LauncherView(state: state, service: service))
        return panel
    }
}

private final class LauncherPanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

@MainActor
private final class LauncherState: ObservableObject {
    @Published var query = "" { didSet { selected = 0 } }
    @Published var selected = 0
}

private struct LauncherView: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var service: MacroService
    @FocusState private var focused: Bool

    var body: some View {
        let results = service.library.search(state.query)
        VStack(spacing: 0) {
            HStack(spacing: PocketSpacing.s) {
                Image(systemName: "wand.and.stars").font(.title3).foregroundStyle(.secondary)
                TextField("Makro ara ve çalıştır", text: $state.query).textFieldStyle(.plain).font(.title3).focused($focused)
            }
            .padding(.horizontal, PocketSpacing.l)
            .frame(height: 52)
            Divider().opacity(0.5)
            if results.isEmpty {
                Text(service.library.macros.isEmpty ? "Henüz makro yok" : "Eşleşen makro yok")
                    .font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, macro in
                            HStack(spacing: PocketSpacing.m) {
                                Image(systemName: macro.symbol).frame(width: 22)
                                Text(macro.name)
                                Spacer()
                                if let trigger = macro.trigger { Text(verbatim: trigger.displayName).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, PocketSpacing.m).padding(.vertical, PocketSpacing.s)
                            .background(index == state.selected ? Color.accentColor.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(PocketSpacing.s)
                }
            }
        }
        .frame(width: 520, height: 340)
        .modifier(LauncherSurface())
        .onAppear { focused = true }
    }
}

private struct LauncherSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThickMaterial, in: shape).overlay { shape.strokeBorder(.primary.opacity(0.1)) }.clipShape(shape)
        }
    }
}
