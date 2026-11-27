import AppKit
import ApplicationServices
import MacPocketCore
import MacPocketSSH

@MainActor
final class CommandBarService: ObservableObject {
    static let shared = CommandBarService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("CommandBarService")
    #endif

    struct Entry: Identifiable {
        enum Target {
            case tool(String), practical(PracticalTool), quick(QuickAction), application(URL), window(String)
            case clipboard(UUID), parameter(ParameterCommand), ssh(SSHSection), sshQuickConnect
        }
        let search: CommandSearchEntry
        let symbol: String
        let target: Target
        var id: String { search.id }
        var canRemember: Bool { id != "parameter" && ![.window, .clipboard].contains(search.kind) }
    }

    @Published var query = "" { didSet { updateResults(reset: true) } }
    @Published var kind: CommandSearchEntry.Kind? { didSet { updateResults(reset: true) } }
    @Published private(set) var results: [Entry] = []
    @Published var selectedID: String?
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published private(set) var shortcutRegistered = false
    @Published var shortcut: KeyCombo? = {
        guard let data = UserDefaults.standard.data(forKey: shortcutKey) else { return KeyCombo(keyCode: 49, modifiers: [.option]) }
        return (try? JSONDecoder().decode(KeyCombo?.self, from: data)) ?? nil
    }() {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: Self.shortcutKey)
            registerShortcut()
        }
    }
    var recordingShortcut = false { didSet { registerShortcut() } }
    private(set) var moduleRunning = false
    private weak var model: PocketModel?
    private var entries: [Entry] = []
    private var windowCatalog = WindowCatalog()
    private let inventory = ApplicationInventory()
    private var applications: [InstalledApplication] = []
    private var applicationsReadAt = Date.distantPast
    private var refreshTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var previousApplication: NSRunningApplication?
    private lazy var hotKey = PocketGlobalHotKey { [weak self] in self?.toggle() }
    private lazy var panel = CommandBarPanelController(service: self)
    private var recent = UserDefaults.standard.stringArray(forKey: "MacPocket.commandBar.recent") ?? []
    @Published private(set) var pinned = Set(UserDefaults.standard.stringArray(forKey: "MacPocket.commandBar.pinned") ?? [])
    private static let shortcutKey = "MacPocket.commandBar.shortcut"

    private init() {}

    func start(model: PocketModel) {
        guard !moduleRunning, PocketModule.commandBar.isAvailable() else { return }
        self.model = model
        moduleRunning = true
        registerShortcut()
    }

    func stopForModule() {
        moduleRunning = false
        close()
        hotKey.unregister()
        shortcutRegistered = false
        model = nil
        applications = []
        windowCatalog = WindowCatalog()
        applicationsReadAt = .distantPast
    }

    private static func includes(_ source: String) -> Bool {
        UserDefaults.standard.object(forKey: "MacPocket.commandBar." + source) as? Bool ?? true
    }

    func clearRecent() {
        recent = []
        UserDefaults.standard.removeObject(forKey: "MacPocket.commandBar.recent")
        updateResults(reset: false)
    }

    private func registerShortcut() {
        guard moduleRunning, !recordingShortcut, let shortcut else {
            hotKey.unregister()
            shortcutRegistered = false
            return
        }
        shortcutRegistered = hotKey.register(shortcut)
    }

    func toggle() { panel.isVisible ? close() : show() }

    func show() {
        guard moduleRunning else { return }
        if !panel.isVisible { previousApplication = NSWorkspace.shared.frontmostApplication }
        query = ""
        kind = nil
        message = nil
        refreshGeneration = UUID()
        let generation = refreshGeneration
        entries = builtInEntries()
        updateResults(reset: true)
        panel.show()
        refreshTask?.cancel()
        loading = true
        // Dynamic discovery only runs while the palette is open. No polling or window capture is needed.
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if Self.includes("applications"), Date().timeIntervalSince(applicationsReadAt) > 60 {
                do {
                    let found = try await inventory.scan()
                    guard !Task.isCancelled, refreshGeneration == generation else { return }
                    applications = found
                    applicationsReadAt = Date()
                } catch {
                    guard !Task.isCancelled, refreshGeneration == generation else { return }
                    message = error.localizedDescription
                }
            }
            guard !Task.isCancelled, refreshGeneration == generation else { return }
            if Self.includes("applications") {
                entries += applications.map { app in
                    Entry(search: .init(id: "app:\(app.url.path)", title: app.name, subtitle: app.url.deletingLastPathComponent().path,
                                        keywords: app.bundleID, kind: .application), symbol: "app", target: .application(app.url))
                }
            }
            updateResults(reset: false)
            if Self.includes("windows") {
                let report = await windowCatalog.snapshot()
                guard !Task.isCancelled, refreshGeneration == generation else { return }
                if !report.accessibilityGranted { message = String(localized: "Pencere başlıkları ve pencere seçimi için Erişilebilirlik izni gerekir.") }
                entries += report.windows.filter { $0.processID != getpid() && $0.isRealWindow }.map { window in
                    Entry(search: .init(id: "window:\(window.id)", title: window.title.isEmpty ? window.application : window.title,
                                        subtitle: window.application, kind: .window), symbol: "macwindow", target: .window(window.id))
                }
            }
            loading = false
            updateResults(reset: false)
        }
    }

    func close() {
        pasteTask?.cancel()
        pasteTask = nil
        refreshGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        loading = false
        panel.close()
        entries = []
        results = []
        selectedID = nil
    }

    private func builtInEntries() -> [Entry] {
        let first = ["screenshot", "window-switcher", "clipboard", "screen-grab", "brightness", "quick-actions"]
        let catalog = HubTool.catalog.enumerated().sorted { a, b in
            let left = first.firstIndex(of: a.element.id) ?? (first.count + a.offset)
            let right = first.firstIndex(of: b.element.id) ?? (first.count + b.offset)
            return left < right
        }.map(\.element)
        var rows = catalog.map { tool in
            Entry(search: .init(id: "tool:\(tool.id)", title: tool.title, subtitle: tool.description,
                                keywords: tool.searchKeywords, kind: .tool), symbol: tool.icon, target: .tool(tool.id))
        }
        rows += NetworkTab.allCases.map { tab in
            Entry(search: .init(id: "tool:\(tab.id)", title: tab.title, subtitle: tab.detail,
                                keywords: tab.id + " " + String(localized: "Ağ Yönetimi"), kind: .tool), symbol: tab.symbol, target: .tool(tab.id))
        }
        rows += ApplicationsSection.searchable.map { section in
            Entry(search: .init(id: "tool:\(section.id)", title: section.title, subtitle: section.detail,
                                keywords: section.searchKeywords + " " + PocketPage.applications.localizedTitle, kind: .tool),
                  symbol: section.symbol, target: .tool(section.id))
        }
        rows += PracticalTool.allCases.map { tool in
            Entry(search: .init(id: "practical:\(tool.id)", title: tool.localizedTitle, subtitle: tool.detail,
                                keywords: tool.id, kind: .tool), symbol: tool.symbol, target: .practical(tool))
        }
        rows += QuickAction.allCases.map { action in
            Entry(search: .init(id: "action:\(action.id)", title: action.title,
                                subtitle: action.needsConfirmation ? String(localized: "Onaylamak için Hızlı İşlemler’i aç") : action.detail,
                                kind: .action), symbol: action.symbol, target: .quick(action))
        }
        if Self.includes("clipboard"), PocketModule.clipboard.isAvailable() {
            rows += ClipboardService.shared.history.items.prefix(1000).map { item in
                Entry(search: .init(id: "clipboard:\(item.id)", title: item.title,
                                    subtitle: String(localized: "Pano Geçmişi") + (item.sourceName.map { " · " + $0 } ?? ""),
                                    keywords: String((item.content.plainText ?? "").prefix(4096)), kind: .clipboard), symbol: "doc.on.clipboard", target: .clipboard(item.id))
            }
        }
        rows += SSHSection.allCases.map { section in
            Entry(search: .init(id: "ssh:" + section.rawValue,
                                title: section.localizedTitle, subtitle: String(localized: "SSH Yöneticisi"),
                                keywords: "ssh config host server key known_hosts backup terminal", kind: .tool),
                  symbol: section.icon, target: .ssh(section))
        }
        rows.append(Entry(search: .init(id: "ssh:quick-connect", title: String(localized: "SSH Hızlı Bağlan"),
                                        keywords: "ssh connect terminal", kind: .action),
                          symbol: "terminal", target: .sshQuickConnect))
        return rows
    }

    private func updateResults(reset: Bool) {
        var candidates = entries
        var parameterID: String?
        if let parameter = ParameterCommand.parse(query) {
            let title: String
            let symbol: String
            switch parameter {
            case .brightness(let percent): title = String(localized: "Parlaklığı \(pocketPercent(Double(percent))) yap")
            symbol = "sun.max"
            case .keepAwake(let minutes): title = String(localized: "\(minutes) dakika uyanık tut")
            symbol = "cup.and.saucer"
            }
            let row = Entry(search: .init(id: "parameter", title: title, subtitle: String(localized: "Komutu çalıştır"), kind: .action),
                            symbol: symbol, target: .parameter(parameter))
            candidates.insert(row, at: 0)
            parameterID = row.id
        }
        let ordered = CommandSearch.results(candidates.map(\.search), query: query, kind: kind, recent: recent, pinned: pinned)
        let map = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        results = ordered.compactMap { map[$0.id] }
        // A validated parameter command is an exact action, even when its localized title differs from the
        // input.
        if let parameterID, kind == nil || kind == .action, let row = map[parameterID] {
            results.removeAll { $0.id == parameterID }
            results.insert(row, at: 0)
        }
        if reset || !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id }
    }

    func move(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(index + offset, 0), results.count - 1)].id
    }

    func togglePin(_ row: Entry) {
        guard row.canRemember else { return }
        if !pinned.insert(row.id).inserted { pinned.remove(row.id) }
        UserDefaults.standard.set(pinned.sorted(), forKey: "MacPocket.commandBar.pinned")
        updateResults(reset: false)
    }

    func executeSelected() {
        guard let row = results.first(where: { $0.id == selectedID }) else { return }
        execute(row)
    }

    func execute(_ row: Entry) {
        guard moduleRunning else { return }
        if row.canRemember, row.id != "parameter" {
            recent = Array(([row.id] + recent.filter { $0 != row.id }).prefix(30))
            UserDefaults.standard.set(recent, forKey: "MacPocket.commandBar.recent")
        }
        close()
        switch row.target {
        case .ssh(let section): SSHRuntime.shared.open(section)
        case .sshQuickConnect: SSHRuntime.shared.showQuickConnect()
        case .tool(let id): openTool(id)
        case .practical(let tool):
            PracticalWorkspace.shared.selected = tool
            model?.navigation.open(.practical)
            model?.openMainWindow?()
        case .quick(let action):
            if action.needsConfirmation { openTool("quick-actions") }
            else {
                QuickActionService.shared.perform(action) { outcome in
                    if let outcome { PocketToast.show(outcome.text, symbol: "info.circle") }
                }
            }
        case .application(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { Task { @MainActor in PocketToast.show(error.localizedDescription, symbol: "exclamationmark.triangle") } }
            }
        case .window(let id):
            Task { do { try await windowCatalog.focus(id) } catch { PocketToast.show(error.localizedDescription, symbol: "exclamationmark.triangle") } }
        case .clipboard(let id):
            guard PocketModule.clipboard.isAvailable(), let item = ClipboardService.shared.history.items.first(where: { $0.id == id }) else { return }
            guard ClipboardService.shared.copy(item) else {
                if let error = ClipboardService.shared.lastError { PocketToast.show(error, symbol: "exclamationmark.triangle") }
                return
            }
            if ClipboardService.shared.settings.pasteOnSelect { pasteIntoPreviousApplication(requiredModule: .clipboard) }
        case .parameter(let command): executeParameter(command)
        }
    }

    private func openTool(_ id: String) {
        if id == "shelf", PocketModule.shelf.isAvailable() { ShelfService.shared.show(); return }
        model?.openCatalogTool(id)
        model?.openMainWindow?()
    }

    private func executeParameter(_ command: ParameterCommand) {
        switch command {
        case .keepAwake(let minutes):
            Task {
                await model?.startAwake(duration: Double(minutes) * 60)
                if let error = model?.awakeError { PocketToast.show(error, symbol: "exclamationmark.triangle") }
                else { PocketToast.show(String(localized: "Mac \(minutes) dakika uyanık tutulacak"), symbol: "cup.and.saucer") }
            }
        case .brightness(let percent):
            guard PocketModule.displays.isAvailable() else { openTool("brightness"); return }
            let service = DisplayBrightnessService.shared
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
            let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = service.displays.first(where: { $0.id == id }) else { openTool("brightness"); return }
            service.setLevel(Double(percent) / 100, for: display.id)
            if let actual = service.displays.first(where: { $0.id == display.id }) {
                PocketToast.show(String(localized: "\(actual.name): \(pocketPercent(actual.level * 100)) parlaklık"), symbol: "sun.max")
            }
        }
    }

    private func pasteIntoPreviousApplication(requiredModule: PocketModule) {
        guard AXIsProcessTrusted(), let target = previousApplication, !target.isTerminated, target.processIdentifier != getpid() else {
            PocketToast.show(String(localized: "Panoya kopyalandı"), symbol: "doc.on.clipboard")
            return
        }
        let pid = target.processIdentifier
        let launch = target.launchDate
        pasteTask?.cancel()
        pasteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            // Do not send a keystroke if the person switched apps while the panel was closing.
            guard !Task.isCancelled, self?.moduleRunning == true, requiredModule.isAvailable(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  NSRunningApplication(processIdentifier: pid)?.launchDate == launch else { return }
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.setIntegerValueField(.eventSourceUserData, value: PocketSyntheticKey.marker)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}

#if DEBUG
extension CommandBarService {
    var diagnosticPanelWindow: NSWindow? { panel.diagnosticWindow }
    var diagnosticPanelResign: [String: Bool]? { panel.diagnosticResign }
    var moduleDiagnosticResources: [String: Int] {
        panel.diagnosticResources.merging(["discoveryTask": refreshTask == nil ? 0 : 1, "shortcut": shortcutRegistered ? 1 : 0]) { a, _ in a }
    }
}
#endif
