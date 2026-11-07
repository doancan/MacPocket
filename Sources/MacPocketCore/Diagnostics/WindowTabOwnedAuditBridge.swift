#if DEBUG
import AppKit
import Foundation

public struct WindowTabOwnedAuditSnapshot {
    public let windows: [SwitchableWindow]
    public let recoveredWindowIDs: [UInt32]
    public let rememberedGroups: Int
    public let partial: Bool
}

/// Own-process formal NSAccessibility transport. It shares production discovery/cache/action
/// logic, but does not pretend to validate the remote AXUIElement transport or grant TCC access.
@MainActor public final class WindowTabOwnedAuditBridge {
    private let io = OwnedWindowTabIO()
    private let adapter: TabAccessibility<OwnedWindowTabIO>
    private var actions: [String: TabAction<NSObject>] = [:]
    public init() { adapter = TabAccessibility(io: io) }
    public var actionAttempts: Int { io.pressCount }

    public func snapshot(listedWindows: [NSWindow], windows: [SwitchableWindow], surfaces: [WindowTabSurface],
                         spaces: WindowSpaceSnapshot) -> WindowTabOwnedAuditSnapshot {
        let pid = getpid()
        guard let launch = CatalogWindowIdentity.processLaunchDate(pid: pid, applicationDate: NSRunningApplication.current.launchDate) else {
            return .init(windows: [], recoveredWindowIDs: [], rememberedGroups: 0, partial: true)
        }
        let process = WindowTabProcess(pid: pid, launchedAt: launch), deadline = Date().addingTimeInterval(2)
        let listed: [NSObject] = listedWindows
        let discovery = adapter.discoverWindows(listed: listed, process: process,
            physicalWindowIDs: Set(surfaces.filter { $0.processID == pid }.map(\.id)), deadline: deadline)
        var values = windows.filter { $0.processID == pid && $0.nativeTab == nil }, scans: [TabScan<NSObject>] = [], owners: [String: WindowTabProcess] = [:]
        for element in discovery.windows {
            guard let window = element as? NSWindow, let id = io.windowID(element),
                  let surface = surfaces.first(where: { $0.id == id && $0.processID == pid }) else { continue }
            let key = CatalogWindowIdentity.window(pid: pid, launchedAt: launch, windowID: id, elementHash: 0)
            let root = SwitchableWindow(id: key, processID: pid, application: Bundle.main.bundleURL.deletingPathExtension().lastPathComponent,
                title: window.title, applicationURL: Bundle.main.bundleURL, minimized: window.isMiniaturized, hidden: NSApp.isHidden,
                fullScreen: window.styleMask.contains(.fullScreen), frontmost: window.isKeyWindow,
                windowAccessible: true, canClose: window.styleMask.contains(.closable), canMinimize: window.styleMask.contains(.miniaturizable),
                canFullScreen: window.styleMask.contains(.resizable), launchedAt: launch, lastFocusedAt: nil,
                windowID: id, frame: surface.frame, spaceMembership: spaces.membership(for: id))
            values.removeAll { $0.windowID == id || (!$0.isRealWindow && $0.processID == pid) }
            values.append(root)
            if let scan = adapter.scan(window: element, anchorID: key, cached: discovery.cachedByWindowID[id] ?? [], deadline: deadline) {
                scans.append(scan); owners[key] = process
            }
        }
        let projection = WindowTabProjectionResolver.project(values, surfaces: surfaces, bars: scans.map(\.bar))
        adapter.commit(scans: scans, processes: owners, projection: projection, liveProcesses: [process], invalidGroups: discovery.invalidGroups)
        actions.removeAll()
        for (id, binding) in projection.bindings {
            guard let scan = scans.first(where: { $0.bar.anchorID == binding.anchorID }), var action = scan.actions[binding.controlID] else { continue }
            action.expectedWindowID = binding.expectedWindowID; actions[id] = action
        }
        let listedIDs = Set(listedWindows.compactMap { io.windowID($0) })
        return .init(windows: projection.windows, recoveredWindowIDs: discovery.windows.compactMap { io.windowID($0) }.filter { !listedIDs.contains($0) },
                     rememberedGroups: adapter.rememberedGroupCount, partial: discovery.partial)
    }
    public func press(_ id: String) throws {
        guard let action = actions[id] else { throw WindowCatalogError.expired }
        try adapter.press(action, processID: getpid())
    }
    public func selectedWindowID(for id: String) -> UInt32? {
        guard let action = actions[id], let window = adapter.selectedWindow(for: action, processID: getpid()) else { return nil }
        return io.windowID(window)
    }
    public func reset() { actions.removeAll(); adapter.reset() }
}

/// NSObject's dynamic getters are invoked only on main by the isolated bridge above. No native
/// accessibility reference is transferred to WindowCatalog's worker actor.
private final class OwnedWindowTabIO: WindowTabIO {
    private(set) var pressCount = 0
    var trusted: Bool { true }
    func equal(_ lhs: NSObject, _ rhs: NSObject) -> Bool { lhs === rhs }
    func processID(_ element: NSObject) -> Int32? { getpid() }
    func windowID(_ element: NSObject) -> UInt32? {
        precondition(Thread.isMainThread)
        let selector = NSSelectorFromString("windowNumber")
        guard element.responds(to: selector) else { return nil }
        typealias Number = @convention(c) (AnyObject, Selector) -> Int
        let id = unsafeBitCast(element.method(for: selector), to: Number.self)(element, selector)
        return id > 0 && id <= Int(UInt32.max) ? UInt32(id) : nil
    }
    func role(_ element: NSObject) -> WindowTabRole {
        guard element.responds(to: NSSelectorFromString("accessibilityRole")) else { return .invalid }
        guard let role = value(element, "accessibilityRole") as? String else { return .unavailable }
        return .value(role)
    }
    func string(_ element: NSObject, attribute: String) -> String? { value(element, "accessibilitySubrole") as? String }
    func flag(_ element: NSObject, attribute: String) -> Bool { (value(element, "accessibilityValue") as? NSNumber)?.boolValue == true }
    func element(_ element: NSObject, attribute: String) -> NSObject? { value(element, "accessibilityWindow") as? NSObject }
    func children(_ element: NSObject, limit: Int) -> [NSObject]? {
        guard let children = value(element, "accessibilityChildren") as? [NSObject], children.count <= limit else { return nil }
        return children
    }
    func tabAttributes(_ element: NSObject) -> WindowTabAttributes? {
        .init(subrole: value(element, "accessibilitySubrole") as? String, title: value(element, "accessibilityTitle") as? String ?? "",
              selected: (value(element, "accessibilityValue") as? NSNumber)?.boolValue == true)
    }
    func setTimeout(_ element: NSObject, seconds: Float) {}
    func press(_ element: NSObject) -> Bool {
        precondition(Thread.isMainThread)
        pressCount += 1
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard element.responds(to: selector) else { return false }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(element.method(for: selector), to: Press.self)(element, selector)
    }
    private func value(_ element: NSObject, _ name: String) -> Any? {
        precondition(Thread.isMainThread)
        let selector = NSSelectorFromString(name)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }
}
#endif
