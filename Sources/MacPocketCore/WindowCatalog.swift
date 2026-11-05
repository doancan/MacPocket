import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct SwitchableWindow: Identifiable, Sendable {
    public let id: String
    public let processID: Int32
    public let application: String
    public let title: String
    public let applicationURL: URL?
    public let minimized: Bool
    public let hidden: Bool
    public let fullScreen: Bool
    public let frontmost: Bool
    /// An AX handle exists, so window actions (close, minimize, raise) are possible.
    public let windowAccessible: Bool
    public let canClose: Bool
    public let canMinimize: Bool
    public let canFullScreen: Bool
    public let launchedAt: Date?
    public let lastFocusedAt: Date?
    /// WindowServer identifier; stable for the window's lifetime and used for thumbnails.
    public var windowID: UInt32? = nil
    /// Global frame in CoreGraphics coordinates (top-left origin).
    public var frame: CGRect? = nil
    /// Display containing the window's center.
    public var displayID: UInt32? = nil
    /// Window lives on another Space (not on screen, not minimized, app not hidden).
    public var otherSpace = false
    /// Front-to-back WindowServer order among on-screen windows; nil when off screen.
    public var zOrder: Int? = nil
    public var canResize = false

    public init(id: String, processID: Int32, application: String, title: String, applicationURL: URL?,
                minimized: Bool, hidden: Bool, fullScreen: Bool, frontmost: Bool, windowAccessible: Bool,
                canClose: Bool, canMinimize: Bool, canFullScreen: Bool, launchedAt: Date?, lastFocusedAt: Date?,
                windowID: UInt32? = nil, frame: CGRect? = nil, displayID: UInt32? = nil,
                otherSpace: Bool = false, zOrder: Int? = nil, canResize: Bool = false) {
        self.id = id; self.processID = processID; self.application = application; self.title = title
        self.applicationURL = applicationURL; self.minimized = minimized; self.hidden = hidden
        self.fullScreen = fullScreen; self.frontmost = frontmost; self.windowAccessible = windowAccessible
        self.canClose = canClose; self.canMinimize = canMinimize; self.canFullScreen = canFullScreen
        self.launchedAt = launchedAt; self.lastFocusedAt = lastFocusedAt; self.windowID = windowID
        self.frame = frame; self.displayID = displayID; self.otherSpace = otherSpace; self.zOrder = zOrder; self.canResize = canResize
    }

    /// A window that exists in WindowServer and can be captured, with or without AX actions.
    public var isRealWindow: Bool { windowID != nil || windowAccessible }
}

public enum WindowSortOrder: String, CaseIterable, Sendable {
    case recent, application, title
}

/// Visibility filters shared by every shortcut.
public struct WindowListFilter: Codable, Equatable, Hashable, Sendable {
    public var includeMinimized = true
    public var includeHidden = true
    public var includeWindowless = false
    public var currentApplicationOnly = false
    public var currentSpaceOnly = false
    public var currentScreenOnly = false
    public init() {}
}

public enum WindowFiltering {
    public static func apply(_ windows: [SwitchableWindow], search: String = "", includeMinimized: Bool = true,
                             includeHidden: Bool = true, includeWindowless: Bool = true, currentApplication: Int32? = nil,
                             excludedBundlePaths: Set<String> = [], order: WindowSortOrder = .recent,
                             currentSpaceOnly: Bool = false, displayID: UInt32? = nil) -> [SwitchableWindow] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let values = windows.filter {
            (includeMinimized || !$0.minimized) && (includeHidden || !$0.hidden)
            && (includeWindowless || $0.isRealWindow)
            && (currentApplication == nil || $0.processID == currentApplication)
            && (!currentSpaceOnly || !$0.otherSpace)
            && (displayID == nil || $0.displayID == nil || $0.displayID == displayID)
            && !excludedBundlePaths.contains($0.applicationURL?.path ?? "")
            && (query.isEmpty || matches(query, "\($0.application) \($0.title)"))
        }
        // Stable ties preserve the server's application/window order.
        return values.enumerated().sorted { a, b in
            switch order {
            case .recent:
                let lhs = a.element.lastFocusedAt ?? .distantPast, rhs = b.element.lastFocusedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                if a.element.frontmost != b.element.frontmost { return a.element.frontmost }
                // Unobserved windows fall back to WindowServer stacking order (front first).
                let lz = a.element.zOrder ?? .max, rz = b.element.zOrder ?? .max
                if lz != rz { return lz < rz }
            case .application:
                let comparison = a.element.application.localizedStandardCompare(b.element.application)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .title:
                let comparison = a.element.title.localizedStandardCompare(b.element.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Every whitespace-separated term must appear, diacritic- and case-insensitively ("goo chr" → Google Chrome).
    static func matches(_ query: String, _ text: String) -> Bool {
        query.split(separator: " ").allSatisfy {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

public struct WindowCatalogReport: Sendable {
    public let windows: [SwitchableWindow]
    public let accessibilityGranted: Bool
    public let partial: Bool
    /// Windows on other Spaces need WindowServer titles, which require Screen Recording access.
    public var otherSpacesVisible = false
}

public enum WindowAction: Sendable { case close, minimize, restore, toggleFullScreen, hideApplication, quitApplication }

public enum WindowCatalogError: Error, LocalizedError {
    case expired, focusFailed, unsupported, permissionRequired
    public var errorDescription: String? {
        switch self {
        case .expired: String(localized: "Pencere ya da uygulama değişti. Listeyi yenile.")
        case .focusFailed: String(localized: "macOS işlemi tamamlayamadı. İzin veya Space durumunu kontrol et.")
        case .unsupported: String(localized: "Bu pencere bu işlemi desteklemiyor.")
        case .permissionRequired: String(localized: "Bu işlem için macOS Erişilebilirlik izni gerekiyor.")
        }
    }
}

/// One WindowServer entry from `CGWindowListCopyWindowInfo`.
struct ServerWindow: Sendable {
    let id: UInt32
    let pid: Int32
    let frame: CGRect
    let title: String?
    let onScreen: Bool
}

/// AX handles remain actor-isolated. Identity is revalidated before every mutation.
public actor WindowCatalog {
    public static var untitledWindowTitle: String { String(localized: "Başlıksız pencere") }
    private struct ApplicationInfo: Sendable {
        let pid: Int32
        let name: String
        let url: URL?
        let launchedAt: Date?
        let frontmost: Bool
        let hidden: Bool
    }
    private struct Handle { let application: ApplicationInfo; let window: AXUIElement?; let windowID: UInt32? }
    private var handles: [String: Handle] = [:]
    private var focusHistory: [String: Date] = [:]
    private var applicationHistory: [Int32: Date] = [:]
    public init() {}

    public func noteApplicationActivation(_ pid: Int32) { if pid != getpid() { applicationHistory[pid] = Date() } }

    public func snapshot(processIDs: Set<Int32>? = nil, includingCurrentApplication: Bool = false, matchingApplicationURL: URL? = nil) async -> WindowCatalogReport {
        let (candidates, screens) = await MainActor.run { () -> ([ApplicationInfo], [(UInt32, CGRect)]) in
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let apps = NSWorkspace.shared.runningApplications.filter {
                ($0.activationPolicy == .regular || (includingCurrentApplication && $0.processIdentifier == getpid()))
                    && (includingCurrentApplication || $0.processIdentifier != getpid())
                    && (processIDs?.contains($0.processIdentifier) ?? true)
            }.map {
                ApplicationInfo(pid: $0.processIdentifier, name: $0.localizedName ?? String(localized: "Uygulama"), url: $0.bundleURL,
                                launchedAt: $0.launchDate, frontmost: $0.processIdentifier == front, hidden: $0.isHidden)
            }.sorted { $0.frontmost && !$1.frontmost }
            return (apps, Self.displayFrames())
        }
        let apps: [ApplicationInfo]
        if let matchingApplicationURL {
            let canonical = matchingApplicationURL.standardizedFileURL.resolvingSymlinksInPath()
            apps = candidates.filter { $0.url?.standardizedFileURL.resolvingSymlinksInPath() == canonical }
        } else { apps = candidates }
        let trusted = AXIsProcessTrusted()
        let server = Self.serverWindows()
        let zOrder = Self.onScreenOrder()
        let titlesReadable = server.values.joined().contains { $0.title?.isEmpty == false }
        let deadline = Date().addingTimeInterval(8)
        var partial = false
        var values: [SwitchableWindow] = []
        var nextHandles: [String: Handle] = [:]
        func display(for frame: CGRect?) -> UInt32? {
            guard let frame else { return nil }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return screens.first { $0.1.contains(center) }?.0
                ?? screens.max { $0.1.intersection(frame).area < $1.1.intersection(frame).area }.map(\.0)
        }

        for app in apps {
            if Task.isCancelled || Date() >= deadline || values.count >= 300 { partial = true; break }
            let appKey = "\(app.pid)-\(app.launchedAt?.timeIntervalSince1970 ?? 0)"
            var serverWindows = server[app.pid] ?? []
            var produced = 0

            if trusted {
                let element = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(element, 0.2)
                let elements = (Self.attribute(element, kAXWindowsAttribute) as? [AXUIElement]) ?? []
                let focused = Self.elementAttribute(element, kAXFocusedWindowAttribute)
                for window in elements.prefix(80) {
                    if Task.isCancelled || Date() >= deadline { partial = true; break }
                    AXUIElementSetMessagingTimeout(window, 0.2)
                    // Only standard windows are switch targets (drawers, sheets and palettes are not).
                    let subrole = Self.attribute(window, kAXSubroleAttribute) as? String
                    if let subrole, subrole != kAXStandardWindowSubrole as String, subrole != "AXDialog" { continue }
                    let axFrame = Self.frame(of: window)
                    let windowID = Self.windowID(of: window) ?? axFrame.flatMap { frame in
                        serverWindows.first { $0.frame.isApproximately(frame) }?.id
                    }
                    let matched = windowID.flatMap { id in serverWindows.firstIndex { $0.id == id } }
                    let serverEntry = matched.map { serverWindows.remove(at: $0) }
                    let id = windowID.map { "w-\(appKey)-\($0)" } ?? "window-\(appKey)-\(CFHash(window))"
                    let front = app.frontmost && focused.map { CFEqual($0, window) } == true
                    if front { focusHistory[id] = Date() }
                    let close = Self.elementAttribute(window, kAXCloseButtonAttribute)
                    let closable = close.map { (Self.attribute($0, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true } ?? false
                    let frame = serverEntry?.frame ?? axFrame
                    let title = (Self.attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? serverEntry?.title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.untitledWindowTitle
                    nextHandles[id] = Handle(application: app, window: window, windowID: windowID)
                    values.append(.init(id: id, processID: app.pid, application: app.name, title: title,
                                        applicationURL: app.url, minimized: Self.boolean(window, kAXMinimizedAttribute), hidden: app.hidden,
                                        fullScreen: Self.boolean(window, "AXFullScreen"), frontmost: front, windowAccessible: true,
                                        canClose: closable, canMinimize: Self.settable(window, kAXMinimizedAttribute),
                                        canFullScreen: Self.settable(window, "AXFullScreen"), launchedAt: app.launchedAt,
                                        lastFocusedAt: focusHistory[id] ?? applicationHistory[app.pid],
                                        windowID: windowID, frame: frame, displayID: display(for: frame),
                                        otherSpace: false, zOrder: windowID.flatMap { zOrder[$0] },
                                        canResize: Self.settable(window, kAXPositionAttribute) && Self.settable(window, kAXSizeAttribute)))
                    produced += 1
                }
                if elements.count > 80 { partial = true }
            }

            // WindowServer-only windows: on other Spaces (AX lists the current Space only), or every window when
            // AX is not granted. Without titles (no Screen Recording) off-screen entries cannot be told apart
            // from invisible helper windows, so they are not guessed.
            if !app.hidden {
                for entry in serverWindows {
                    let titled = entry.title?.isEmpty == false
                    let otherSpace = !entry.onScreen
                    guard titled || (!trusted && entry.onScreen), !(otherSpace && !titled),
                          screens.contains(where: { $0.1.intersects(entry.frame) }) else { continue }
                    let id = "w-\(appKey)-\(entry.id)"
                    nextHandles[id] = Handle(application: app, window: nil, windowID: entry.id)
                    values.append(.init(id: id, processID: app.pid, application: app.name,
                                        title: entry.title.flatMap { $0.isEmpty ? nil : $0 } ?? app.name,
                                        applicationURL: app.url, minimized: false, hidden: false, fullScreen: false,
                                        frontmost: false, windowAccessible: false, canClose: false, canMinimize: false,
                                        canFullScreen: false, launchedAt: app.launchedAt,
                                        lastFocusedAt: focusHistory[id] ?? applicationHistory[app.pid],
                                        windowID: entry.id, frame: entry.frame, displayID: display(for: entry.frame),
                                        otherSpace: otherSpace && trusted, zOrder: zOrder[entry.id]))
                    produced += 1
                }
            }

            if produced == 0 {
                let id = "app-" + appKey
                nextHandles[id] = Handle(application: app, window: nil, windowID: nil)
                values.append(.init(id: id, processID: app.pid, application: app.name,
                                    title: trusted ? String(localized: "Açık pencere yok") : String(localized: "Pencere erişimi bekleniyor"),
                                    applicationURL: app.url, minimized: false, hidden: app.hidden, fullScreen: false,
                                    frontmost: app.frontmost, windowAccessible: false, canClose: false, canMinimize: false,
                                    canFullScreen: false, launchedAt: app.launchedAt, lastFocusedAt: applicationHistory[app.pid]))
            }
            await Task.yield()
        }
        handles = nextHandles
        focusHistory = focusHistory.filter { nextHandles[$0.key] != nil }
        let livePIDs = Set(apps.map(\.pid)); applicationHistory = applicationHistory.filter { livePIDs.contains($0.key) }
        return .init(windows: values, accessibilityGranted: trusted, partial: partial, otherSpacesVisible: titlesReadable)
    }

    public func focus(_ id: String) async throws {
        try Task.checkCancellation()
        let handle = try await validatedHandle(id)
        let info = handle.application
        let activated = await MainActor.run { () -> Bool in
            guard !Task.isCancelled, let app = NSRunningApplication(processIdentifier: info.pid), app.launchDate == info.launchedAt else { return false }
            app.unhide()
            // A windowless app gets the Dock-click behaviour (reopen), which usually opens a new window.
            if handle.window == nil, handle.windowID == nil, let url = app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
            return app.activate(options: [])
        }
        guard activated else { throw WindowCatalogError.expired }
        try Task.checkCancellation()
        if let window = handle.window {
            try raise(window)
        } else if let windowID = handle.windowID, AXIsProcessTrusted() {
            // Activating the app moves to its Space; the window then becomes visible to AX and can be raised.
            var raised = false
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(70))
                let element = AXUIElementCreateApplication(info.pid)
                AXUIElementSetMessagingTimeout(element, 0.2)
                let windows = (Self.attribute(element, kAXWindowsAttribute) as? [AXUIElement]) ?? []
                if let window = windows.first(where: { Self.windowID(of: $0) == windowID }) {
                    try raise(window)
                    raised = true
                    break
                }
            }
            guard raised else { throw WindowCatalogError.focusFailed }
        }
        focusHistory[id] = Date()
    }

    private func raise(_ window: AXUIElement) throws {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { throw WindowCatalogError.focusFailed }
    }

    public func perform(_ action: WindowAction, on id: String) async throws {
        let handle = try await validatedHandle(id)
        try Task.checkCancellation()
        switch action {
        case .hideApplication, .quitApplication:
            let info = handle.application
            let result = await MainActor.run { () -> Bool in
                guard !Task.isCancelled, let app = NSRunningApplication(processIdentifier: info.pid), app.launchDate == info.launchedAt else { return false }
                // terminate() asks the app to quit normally; it may show its own save prompt.
                return action == .hideApplication ? app.hide() : app.terminate()
            }
            guard result else { throw WindowCatalogError.focusFailed }
            return
        default: break
        }
        guard AXIsProcessTrusted() else { throw WindowCatalogError.permissionRequired }
        guard let window = handle.window else { throw WindowCatalogError.unsupported }
        let result: AXError
        switch action {
        case .close:
            guard let button = Self.attribute(window, kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() else { throw WindowCatalogError.unsupported }
            let close = unsafeDowncast(button, to: AXUIElement.self)
            guard (Self.attribute(close, kAXEnabledAttribute) as? NSNumber)?.boolValue != false else { throw WindowCatalogError.unsupported }
            result = AXUIElementPerformAction(close, kAXPressAction as CFString)
        case .minimize, .restore:
            guard Self.settable(window, kAXMinimizedAttribute) else { throw WindowCatalogError.unsupported }
            let value = NSNumber(value: action == .minimize)
            result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
        case .toggleFullScreen:
            guard Self.settable(window, "AXFullScreen") else { throw WindowCatalogError.unsupported }
            result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, NSNumber(value: !Self.boolean(window, "AXFullScreen")))
        case .hideApplication, .quitApplication: return
        }
        guard result == .success else { throw WindowCatalogError.focusFailed }
    }

    /// Layout the selected catalog window, never whichever window happens to be frontmost.
    public func layout(_ action: WindowLayoutAction, on id: String, gap: CGFloat = 8) async throws {
        let handle = try await validatedHandle(id)
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw WindowCatalogError.permissionRequired }
        guard gap.isFinite, (0...100).contains(gap), action != .restore else { throw WindowCatalogError.unsupported }
        guard let window = handle.window, let frame = Self.frame(of: window),
              Self.settable(window, kAXPositionAttribute), Self.settable(window, kAXSizeAttribute),
              !Self.boolean(window, "AXFullScreen") else { throw WindowCatalogError.unsupported }
        let target = await MainActor.run { () -> CGRect? in
            let screens = NSScreen.screens.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
            guard let primaryHeight = NSScreen.screens.first?.frame.maxY,
                  let source = screens.max(by: { $0.frame.intersection(WindowLayoutGeometry.flip(frame, primaryHeight: primaryHeight)).area
                      < $1.frame.intersection(WindowLayoutGeometry.flip(frame, primaryHeight: primaryHeight)).area }) else { return nil }
            let current = WindowLayoutGeometry.flip(frame, primaryHeight: primaryHeight)
            let target: CGRect?
            if action == .nextDisplay || action == .previousDisplay {
                guard screens.count > 1, let index = screens.firstIndex(of: source) else { return nil }
                let next = (index + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count
                target = WindowLayoutGeometry.move(current, from: source.visibleFrame, to: screens[next].visibleFrame)
            } else {
                target = WindowLayoutGeometry.frame(for: action, in: source.visibleFrame, gap: gap, current: current)
            }
            return target.map { WindowLayoutGeometry.flip($0, primaryHeight: primaryHeight) }
        }
        guard let target else { throw WindowCatalogError.unsupported }
        _ = try await validatedHandle(id)
        try Task.checkCancellation()
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard FocusedWindow(element: window, processID: handle.application.pid).setFrame(target) else { throw WindowCatalogError.focusFailed }
    }

    private func validatedHandle(_ id: String) async throws -> Handle {
        guard let handle = handles[id] else { throw WindowCatalogError.expired }
        let info = handle.application
        let valid = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: info.pid) else { return false }
            return app.launchDate == info.launchedAt
        }
        guard valid else { throw WindowCatalogError.expired }
        if let window = handle.window {
            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success, pid == info.pid else { throw WindowCatalogError.expired }
        }
        return handle
    }

    // MARK: WindowServer

    /// Normal-layer windows grouped by owner. Titles are present only with Screen Recording access.
    static func serverWindows() -> [Int32: [ServerWindow]] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [Int32: [ServerWindow]] = [:]
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 80, bounds.height >= 50,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            result[pid, default: []].append(.init(id: id, pid: pid, frame: bounds, title: info[kCGWindowName as String] as? String,
                                                  onScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? false))
        }
        return result
    }

    /// Front-to-back index of on-screen windows.
    static func onScreenOrder() -> [UInt32: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [UInt32: Int] = [:]
        for (index, info) in list.enumerated() {
            if let id = info[kCGWindowNumber as String] as? UInt32 { order[id] = index }
        }
        return order
    }

    /// Displays in CoreGraphics global coordinates (top-left origin), matching CGWindow bounds and AX frames.
    @MainActor public static func displayFrames() -> [(UInt32, CGRect)] {
        guard let primary = NSScreen.screens.first?.frame else { return [] }
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let f = screen.frame
            return (number.uint32Value, CGRect(x: f.minX, y: primary.maxY - f.maxY, width: f.width, height: f.height))
        }
    }

    // MARK: AX helpers

    private typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// `_AXUIElementGetWindow` maps an AX window to its WindowServer id. It is not public SDK API, so it is
    /// looked up at runtime and every caller falls back to frame matching when it is unavailable.
    private static let axGetWindow: AXGetWindowFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: AXGetWindowFunction.self)
    }()

    private static func windowID(of window: AXUIElement) -> UInt32? {
        guard let axGetWindow else { return nil }
        var id = CGWindowID(0)
        return axGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }; return value
    }
    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private static func boolean(_ element: AXUIElement, _ name: String) -> Bool { (attribute(element, name) as? NSNumber)?.boolValue ?? false }
    private static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var value = DarwinBoolean(false); return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }
    @MainActor public static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
    func isApproximately(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
