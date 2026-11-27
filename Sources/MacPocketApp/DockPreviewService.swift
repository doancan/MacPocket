import AppKit
import ApplicationServices
import MacPocketCore

@MainActor
final class DockPreviewService: ObservableObject {
    static let shared = DockPreviewService()
    #if DEBUG
    private let moduleProbe = ModuleServiceProbe("DockPreviewService")
    #endif
    @Published var settings = DockPreviewSettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            close()
            reconcileMonitoring()
        }
    }
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var captureAllowed = WindowPreviewProvider.permitted
    @Published private(set) var windows: [SwitchableWindow] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var unavailableImages: Set<String> = []
    @Published private(set) var target: DockHoverItem?
    @Published var selectedID: String?
    @Published private(set) var loading = false
    @Published private(set) var partial = false
    @Published private(set) var otherSpacesVisible = false
    @Published private(set) var message: String?
    @Published private(set) var actionBusyID: String?
    @Published private(set) var monitorFailed = false
    private(set) var moduleRunning = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var appObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pointerTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var resolver = DockItemResolver()
    private var catalog = WindowCatalog()
    private var previews = WindowPreviewProvider()
    private var candidate: DockHoverItem?
    private var session = UUID()
    private var monitorSession = UUID()
    private var pointer = CGPoint.zero
    private var visibleIDs: Set<String> = []
    private var attemptedIDs: Set<String> = []
    private var menuDepth = 0
    private var keyboardPointer: CGPoint?
    #if DEBUG
    private var diagnosticMode = false
    private(set) var diagnosticIgnoredEvents: [String] = []
    #endif
    private lazy var panel = DockPreviewPanelController(service: self)
    private init() {}

    var edge: DockEdge {
        DockEdge(rawValue: UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String ?? "bottom") ?? .bottom
    }
    var selected: SwitchableWindow? { windows.first { $0.id == selectedID } }
    var menuIsOpen: Bool { menuDepth > 0 }

    func start() {
        guard !moduleRunning, PocketModule.dockPreview.isAvailable() else { return }
        moduleRunning = true
        settings = DockPreviewSettings.load()
        appObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                #if DEBUG
                if self?.diagnosticMode == true { self?.diagnosticIgnoredEvents.append("applicationActivated"); return }
                #endif
                self?.updatePermissions()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let saved = DockPreviewSettings.load()
                if self.settings != saved { self.settings = saved }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let processID = app?.processIdentifier
                let bundleID = app?.bundleIdentifier
                MainActor.assumeIsolated {
                    #if DEBUG
                    if self?.diagnosticMode == true { self?.diagnosticIgnoredEvents.append(name.rawValue); return }
                    #endif
                    self?.handleWorkspaceChange(name, processID: processID, bundleID: bundleID)
                }
            })
        }
        workspaceObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        updatePermissions()
    }

    func handleWorkspaceChange(_ name: Notification.Name, processID: Int32?, bundleID: String?) {
        if name == NSWorkspace.didActivateApplicationNotification, processID == getpid() { return }
        if (name == NSWorkspace.didActivateApplicationNotification || name == NSWorkspace.activeSpaceDidChangeNotification), actionBusyID != nil { return }
        if name == NSWorkspace.didTerminateApplicationNotification, let processID, bundleID != "com.apple.dock",
           target?.processIDs.contains(processID) != true, candidate?.processIDs.contains(processID) != true { return }
        close()
        if name == NSWorkspace.didTerminateApplicationNotification { resolver = DockItemResolver() }
    }

    func stopForModule() {
        moduleRunning = false
        close()
        removeMonitors()
        if let appObserver { NotificationCenter.default.removeObserver(appObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        appObserver = nil
        defaultsObserver = nil
        for observer in workspaceObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        resolver = DockItemResolver()
        catalog = WindowCatalog()
        previews = WindowPreviewProvider()
    }

    func updatePermissions() {
        trusted = AXIsProcessTrusted()
        captureAllowed = WindowPreviewProvider.permitted
        if !trusted { close() }
        if !captureAllowed {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnails = [:]
            attemptedIDs = []
            unavailableImages = []
        } else { scheduleThumbnails() }
        reconcileMonitoring()
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        updatePermissions()
    }

    private func reconcileMonitoring() {
        guard moduleRunning, settings.enabled, trusted else { removeMonitors(); monitorFailed = false; return }
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event) }
            return event
        }
        monitorFailed = globalMonitor == nil || localMonitor == nil
        if monitorFailed { removeMonitors() }
    }

    private func removeMonitors() {
        monitorSession = UUID()
        pointerTask?.cancel()
        pointerTask = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handlePointer(_ event: NSEvent) {
        guard moduleRunning, settings.enabled, menuDepth == 0 else { return }
        pointer = NSEvent.mouseLocation
        let inside = panel.frame?.contains(pointer) == true && panel.isVisible
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .scrollWheel {
            if !inside { close() }
            return
        }
        if inside { hideTask?.cancel(); hideTask = nil; return }
        let bridge = target.map { item in panel.frame.map { DockPreviewGeometry.keepsOpen(point: pointer, icon: item.iconFrame, panel: $0, edge: edge) } ?? false } ?? false
        if bridge { hideTask?.cancel(); hideTask = nil } else { scheduleHide() }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              DockPreviewGeometry.nearDock(pointer, screen: screen.frame, edge: edge) else {
            candidate = nil
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        requestPointerProbe()
    }

    private func requestPointerProbe() {
        guard moduleRunning, settings.enabled, trusted, pointerTask == nil,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              DockPreviewGeometry.nearDock(pointer, screen: screen.frame, edge: edge) else { return }
        let generation = monitorSession
        pointerTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(65)) } catch { return }
            guard let self else { return }
            guard let primary = NSScreen.screens.first?.frame.maxY else { pointerTask = nil; return }
            let point = pointer
            let item = await resolver.item(at: point, primaryHeight: primary)
            guard !Task.isCancelled, monitorSession == generation, moduleRunning else { return }
            pointerTask = nil
            guard hypot(pointer.x - point.x, pointer.y - point.y) < 24 else { requestPointerProbe(); return }
            if let item, !settings.excludedPaths.contains(item.applicationURL.path) { receiveHover(item) }
            else { candidate = nil; hoverTask?.cancel(); hoverTask = nil }
        }
    }

    private func receiveHover(_ item: DockHoverItem) {
        hideTask?.cancel()
        hideTask = nil
        if target?.applicationURL == item.applicationURL, panel.isVisible {
            target = item
            return
        }
        if candidate?.applicationURL == item.applicationURL, hoverTask != nil { candidate = item; return }
        hoverTask?.cancel()
        candidate = item
        let generation = monitorSession
        hoverTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(settings.hoverDelayMilliseconds)) } catch { return }
            guard generation == monitorSession, moduleRunning, let item = candidate,
                  item.iconFrame.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) else { hoverTask = nil; return }
            hoverTask = nil
            show(item, focus: false)
        }
    }

    private func scheduleHide() {
        guard panel.isVisible, hideTask == nil else { return }
        hideTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(settings.hideDelayMilliseconds)) } catch { return }
            close()
        }
    }

    func menuChanged(_ open: Bool) {
        menuDepth = max(0, menuDepth + (open ? 1 : -1))
        if open { hideTask?.cancel(); hideTask = nil }
    }

    func show(_ item: DockHoverItem, focus: Bool) {
        close()
        guard moduleRunning else { return }
        target = item
        loading = true
        captureAllowed = WindowPreviewProvider.permitted
        panel.show(anchor: item.iconFrame, edge: edge, focus: focus)
        let generation = session
        catalogTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                let report = await catalog.snapshot(processIDs: target?.processIDs ?? item.processIDs, includingCurrentApplication: true, matchingApplicationURL: item.applicationURL)
                guard !Task.isCancelled, generation == session, moduleRunning else { return }
                apply(report)
                panel.resize(anchor: target?.iconFrame ?? item.iconFrame, edge: edge)
                do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
            } while generation == session
        }
    }

    private func apply(_ report: WindowCatalogReport) {
        let old = selectedID
        windows = WindowFiltering.apply(report.windows, includeWindowless: false, currentSpaceOnly: settings.currentSpaceOnly)
        selectedID = windows.contains { $0.id == old } ? old : windows.first?.id
        loading = false
        partial = report.partial
        otherSpacesVisible = report.otherSpacesVisible
        let live = Set(windows.map(\.id))
        visibleIDs.formIntersection(live)
        thumbnails = thumbnails.filter { live.contains($0.key) }
        unavailableImages.formIntersection(live)
        scheduleThumbnails()
    }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible { visibleIDs.insert(id) }
        else { visibleIDs.remove(id); thumbnails[id] = nil; attemptedIDs.remove(id); unavailableImages.remove(id) }
        scheduleThumbnails()
    }

    private func scheduleThumbnails() {
        #if DEBUG
        if diagnosticMode { return }
        #endif
        guard moduleRunning, panel.isVisible, settings.thumbnails, captureAllowed, thumbnailTask == nil else { return }
        let generation = session
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            repeat {
                guard WindowPreviewProvider.permitted else {
                    captureAllowed = false
                    thumbnails = [:]
                    attemptedIDs = []
                    unavailableImages = []
                    thumbnailTask = nil
                    return
                }
                let targets = windows.filter { visibleIDs.contains($0.id) && !$0.minimized && $0.windowID != nil && (settings.live || !attemptedIDs.contains($0.id)) }.prefix(16)
                await withTaskGroup(of: (String, WindowImage?).self) { group in
                    var iterator = targets.makeIterator()
                    for _ in 0..<3 {
                        guard let window = iterator.next() else { break }
                        group.addTask { [previews] in (window.id, try? await previews.image(for: window, maxPixels: CGSize(width: 480, height: 280))) }
                    }
                    for await (id, image) in group {
                        guard !Task.isCancelled, generation == session else { group.cancelAll(); return }
                        if visibleIDs.contains(id) {
                            attemptedIDs.insert(id)
                            if let image { thumbnails[id] = NSImage(cgImage: image.cgImage, size: .zero); unavailableImages.remove(id) }
                            else { thumbnails[id] = nil; unavailableImages.insert(id) }
                        }
                        if let window = iterator.next() {
                            group.addTask { [previews] in (window.id, try? await previews.image(for: window, maxPixels: CGSize(width: 480, height: 280))) }
                        }
                    }
                }
                guard !Task.isCancelled, generation == session else { return }
                if !settings.live, windows.allSatisfy({ !visibleIDs.contains($0.id) || $0.minimized || $0.windowID == nil || attemptedIDs.contains($0.id) }) { break }
                do { try await Task.sleep(for: .milliseconds(settings.live ? 1300 : 80)) } catch { return }
            } while generation == session
            if generation == session { thumbnailTask = nil }
        }
    }

    func close() {
        #if DEBUG
        diagnosticMode = false
        #endif
        monitorSession = UUID()
        pointerTask?.cancel()
        pointerTask = nil
        session = UUID()
        hoverTask?.cancel()
        hoverTask = nil
        hideTask?.cancel()
        hideTask = nil
        catalogTask?.cancel()
        catalogTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        actionTask?.cancel()
        actionTask = nil
        candidate = nil
        target = nil
        windows = []
        thumbnails = [:]
        selectedID = nil
        visibleIDs = []
        attemptedIDs = []
        unavailableImages = []
        keyboardPointer = nil
        message = nil
        loading = false
        actionBusyID = nil
        menuDepth = 0
        panel.close()
        catalog = WindowCatalog()
        previews = WindowPreviewProvider()
    }

    func moveSelection(_ step: Int) {
        guard !windows.isEmpty else { return }
        keyboardPointer = NSEvent.mouseLocation
        let index = windows.firstIndex { $0.id == selectedID } ?? 0
        selectedID = windows[(index + step % windows.count + windows.count) % windows.count].id
    }

    func selectFromHover(_ id: String) {
        #if DEBUG
        if diagnosticMode { return }
        #endif
        if let point = keyboardPointer, hypot(point.x - NSEvent.mouseLocation.x, point.y - NSEvent.mouseLocation.y) < 3 { return }
        keyboardPointer = nil
        selectedID = id
    }

    enum Action { case focus, window(WindowAction), layout(WindowLayoutAction) }
    func perform(_ action: Action, on window: SwitchableWindow) {
        guard moduleRunning, actionTask == nil, windows.contains(where: { $0.id == window.id }) else { return }
        let generation = session
        let catalog = catalog
        actionBusyID = window.id
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch action {
                case .focus: try await catalog.focus(window.id)
                case .window(let command): try await catalog.perform(command, on: window.id)
                case .layout(let layout): try await catalog.layout(layout, on: window.id, gap: WindowLayoutSettings.load(from: .standard).gap)
                }
                guard !Task.isCancelled, generation == session else { return }
                if case .focus = action { close(); return }
                try await Task.sleep(for: .milliseconds(180))
                if let target {
                    let report = await catalog.snapshot(processIDs: target.processIDs, includingCurrentApplication: true, matchingApplicationURL: target.applicationURL)
                    guard !Task.isCancelled, generation == session else { return }
                    apply(report)
                    panel.resize(anchor: target.iconFrame, edge: edge)
                }
            } catch {
                if generation == session, !(error is CancellationError) { message = error.localizedDescription }
            }
            if generation == session { actionTask = nil; actionBusyID = nil }
        }
    }

    func excludeTarget() {
        guard let url = target?.applicationURL else { return }
        settings.excludedPaths.append(url.path)
    }

    #if DEBUG
    func diagnosticShow(_ item: DockHoverItem, windows: [SwitchableWindow], images: [String: NSImage] = [:]) {
        close()
        diagnosticMode = true
        diagnosticIgnoredEvents = []
        target = item
        self.windows = windows
        thumbnails = images
        selectedID = windows.first?.id
        panel.show(anchor: item.iconFrame, edge: edge, focus: true)
        panel.resize(anchor: item.iconFrame, edge: edge)
    }
    var diagnosticWindow: NSWindow? { panel.window }
    var diagnosticKeyboardState: [String: Bool] { panel.diagnosticKeyboardState }
    var moduleDiagnosticResources: [String: Int] {
        var result = ["globalMonitor": globalMonitor == nil ? 0 : 1, "localMonitor": localMonitor == nil ? 0 : 1,
         "observers": workspaceObservers.count + (appObserver == nil ? 0 : 1) + (defaultsObserver == nil ? 0 : 1),
         "pointer": pointerTask == nil ? 0 : 1, "hover": hoverTask == nil ? 0 : 1, "hide": hideTask == nil ? 0 : 1,
         "catalog": catalogTask == nil ? 0 : 1, "thumbnails": thumbnailTask == nil ? 0 : 1, "action": actionTask == nil ? 0 : 1,
         "images": thumbnails.count, "visiblePanel": panel.isVisible ? 1 : 0]
        result.merge(panel.diagnosticResources, uniquingKeysWith: { _, new in new })
        return result
    }
    #endif
}
