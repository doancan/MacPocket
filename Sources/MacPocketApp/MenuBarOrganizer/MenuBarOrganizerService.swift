import AppKit
import Combine
import SwiftUI
import MacPocketCore

// AX handles are immutable CF references; reads are serialized by the inventory worker.
struct ManagedMenuBarItem: Identifiable, @unchecked Sendable {
    let id: String
    let application: String
    let bundleID: String
    let processID: Int32
    let launchedAt: Date?
    let title: String
    let applicationURL: URL?
    let element: AXUIElement
    let frame: CGRect
    let hidden: Bool
}

/// MenuBarAgent owns visibility; AppKit owns Command-drag ordering, including other apps' items.
@MainActor final class MenuBarOrganizerService: NSObject, ObservableObject {
    static let shared = MenuBarOrganizerService()
    static let enabledKey = "MacPocket.menuBarOrganizer.enabled"
    @Published private(set) var enabled = false
    @Published private(set) var collapsed = false
    @Published private(set) var hiddenApplications = Set<String>()
    @Published private(set) var changingVisibility = false
    @Published private(set) var items: [ManagedMenuBarItem] = []
    @Published private(set) var error: String?
    @Published private(set) var scanning = false
    private var control: NSStatusItem?
    private let visibility = MenuBarVisibilityController()
    private var runningObservation: NSKeyValueObservation?
    private var refreshVisibilityTask: Task<Void, Never>?
    private var collapseRequested = false
    private var observer: NSObjectProtocol?
    private var popover: NSPopover?
    private var generation = UUID()
    private var scanTask: Task<[ManagedMenuBarItem], Never>?
    private struct Application: Sendable { let pid: Int32; let name: String; let url: URL?; let launchedAt: Date?; let bundleID: String }
    private let defaults: UserDefaults
    private let autosavePrefix: String
    init(defaults: UserDefaults = .standard, autosavePrefix: String = "MacPocket.Organizer") {
        self.defaults = defaults
        self.autosavePrefix = autosavePrefix
        hiddenApplications = Set(defaults.stringArray(forKey: "MacPocket.menuBarOrganizer.hiddenApplications") ?? [])
        super.init()
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _,_ in
            Task { @MainActor in
                guard let self, self.collapseRequested else { return }
                self.refreshVisibilityTask?.cancel()
                self.refreshVisibilityTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    self?.setCollapsed(true)
                }
            }
        }
        reconcile()
    }
    var isAvailable: Bool { visibility.isAvailable }
    func setHidden(_ value: Bool, for bundleID: String) {
        guard !bundleID.isEmpty, bundleID != Bundle.main.bundleIdentifier, !bundleID.hasPrefix("com.apple.") else { return }
        if value { hiddenApplications.insert(bundleID) } else { hiddenApplications.remove(bundleID) }
        defaults.set(hiddenApplications.sorted(), forKey: "MacPocket.menuBarOrganizer.hiddenApplications")
        items = items.map { item in
            .init(id: item.id, application: item.application, bundleID: item.bundleID, processID: item.processID, launchedAt: item.launchedAt,
                title: item.title, applicationURL: item.applicationURL, element: item.element, frame: item.frame, hidden: hiddenApplications.contains(item.bundleID))
        }
        if collapseRequested { setCollapsed(true) }
    }
    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.enabledKey)
        reconcile()
    }
    private func reconcile() {
        let hidden = Set(defaults.stringArray(forKey: "MacPocket.menuBarOrganizer.hiddenApplications") ?? [])
        if hidden != hiddenApplications {
            hiddenApplications = hidden
            if collapseRequested { setCollapsed(true) }
        }
        let wanted = defaults.bool(forKey: Self.enabledKey)
        guard wanted != enabled else { return }
        enabled = wanted
        if wanted { createItems() } else { removeItems() }
    }
    private func createItems() {
        let control = NSStatusBar.system.statusItem(withLength: 26)
        control.autosaveName = autosavePrefix + ".Control"
        control.button?.target = self
        control.button?.action = #selector(clicked)
        control.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        control.button?.toolTip = String(localized: "Menü çubuğu düzenleyici · sağ tık: simgeler")
        self.control = control
        // First enable reveals all items while the user configures the hidden group.
        setCollapsed(false)
    }
    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showItems() }
        else { setCollapsed(!collapsed) }
    }
    func setCollapsed(_ value: Bool) {
        guard enabled else { return }
        collapseRequested = value
        if !value {
            visibility.release()
            changingVisibility = false
            collapsed = false
            updateControl()
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let blocked = hiddenApplications.intersection(running).filter { !$0.hasPrefix("com.apple.") && $0 != Bundle.main.bundleIdentifier }
        guard !blocked.isEmpty else { visibility.release(); changingVisibility = false; collapsed = false; updateControl(); return }
        var allowed = running.subtracting(blocked)
        allowed.formUnion(["com.apple.MenuBarAgent", "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.TextInputMenuAgent", "com.apple.Siri", "com.apple.Spotlight", "com.apple.wifi.WiFiAgent", "com.apple.UserNotificationCenter", "com.apple.notificationcenterui", "com.apple.loginwindow"])
        if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
        changingVisibility = true
        visibility.apply(allowing: allowed) { [weak self] error in
            guard let self else { return }
            changingVisibility = false
            if let error { self.error = error } else { collapsed = true; self.error = nil }
            updateControl()
        }
    }
    private func updateControl() {
        let title = collapsed ? String(localized: "Gizlenen simgeleri göster") : String(localized: "Simgeleri gizle")
        control?.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right", accessibilityDescription: title)
        control?.button?.setAccessibilityLabel(title)
    }
    func showItems() {
        guard let button = control?.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 360)
        popover.contentViewController = NSHostingController(rootView: MenuBarOrganizerItemList(service: self))
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Task { await refresh() }
    }
    func refresh() async {
        guard !scanning else { return }
        guard AXIsProcessTrusted() else {
            error = String(localized: "Simgeleri listelemek ve açmak için Erişilebilirlik izni ver.")
            return
        }
        scanning = true
        error = nil
        let token = generation
        defer { scanning = false }
        let hidden = hiddenApplications
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map {
            Application(pid: $0.processIdentifier, name: $0.localizedName ?? String(localized: "Uygulama"), url: $0.bundleURL, launchedAt: $0.launchDate, bundleID: $0.bundleIdentifier ?? "")
        }
        let worker = Task.detached(priority: .userInitiated) { Self.readItems(apps: apps, hidden: hidden) }
        scanTask = worker
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard generation == token, !Task.isCancelled else { return }
        scanTask = nil
        // Restricted items disappear from AX; keep the last known handle until its process exits.
        let current = Set(result.map(\.id))
        let remembered = items.filter { hiddenApplications.contains($0.bundleID) && !current.contains($0.id) && NSRunningApplication(processIdentifier: $0.processID)?.launchDate == $0.launchedAt }
        items = (result + remembered).sorted { $0.frame.minX < $1.frame.minX }
    }
    nonisolated private static func readItems(apps: [Application], hidden: Set<String>) -> [ManagedMenuBarItem] {
        var found: [ManagedMenuBarItem] = []
        let deadline = ContinuousClock.now + .seconds(5)
        for app in apps {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { break }
            let root = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root, 0.12)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
                  let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            let menuBar = unsafeDowncast(bar, to: AXUIElement.self)
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &children) == .success,
                  let elements = children as? [AXUIElement] else { continue }
            for (index, element) in elements.prefix(100).enumerated() {
                guard !Task.isCancelled, ContinuousClock.now < deadline else { break }
                func attribute(_ key: String) -> CFTypeRef? {
                    var value: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, key as CFString, &value)
                    return value
                }
                var position = CGPoint.zero, size = CGSize.zero
                if let p = attribute(kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeDowncast(p, to: AXValue.self), .cgPoint, &position)
                }
                if let s = attribute(kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeDowncast(s, to: AXValue.self), .cgSize, &size)
                }
                guard size.width > 0, size.height > 0 else { continue }
                let title = (attribute(kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (attribute(kAXDescriptionAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? app.name
                found.append(.init(id: "\(app.pid)-\(index)", application: app.name, bundleID: app.bundleID, processID: app.pid, launchedAt: app.launchedAt, title: title,
                    applicationURL: app.url, element: element, frame: CGRect(origin: position, size: size),
                    hidden: hidden.contains(app.bundleID)))
            }
        }
        return found.sorted { $0.frame.minX < $1.frame.minX }
    }
    func open(_ item: ManagedMenuBarItem) {
        popover?.close()
        setCollapsed(false)
        let token = generation
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard generation == token, let app = NSRunningApplication(processIdentifier: item.processID),
                  !app.isTerminated, app.launchDate == item.launchedAt else { return }
            if AXUIElementPerformAction(item.element, kAXPressAction as CFString) != .success {
                error = String(localized: "Bu simge açılamadı. Listeyi yenileyip yeniden dene.")
            }
        }
    }
    private func removeItems() {
        generation = UUID()
        scanTask?.cancel()
        scanTask = nil
        popover?.close()
        popover = nil
        visibility.release()
        changingVisibility = false
        if let control { NSStatusBar.system.removeStatusItem(control) }
        control = nil
        collapsed = false
        items = []
    }
    func stopForModule() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        runningObservation = nil
        refreshVisibilityTask?.cancel()
        refreshVisibilityTask = nil
        collapseRequested = false
        observer = nil
        enabled = false
        removeItems()
    }
#if DEBUG
    var diagnosticFrames: [String:CGRect] {
        var frames: [String:CGRect] = [:]
        frames["control"] = control?.button?.window?.frame
        return frames
    }
#endif
}
