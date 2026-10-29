import AppKit
@preconcurrency import ApplicationServices
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
    public let windowAccessible: Bool
    public let canClose: Bool
    public let canMinimize: Bool
    public let canFullScreen: Bool
    public let launchedAt: Date?
    public let lastFocusedAt: Date?
}

public enum WindowSortOrder: String, CaseIterable, Sendable {
    case recent, application, title
}

public enum WindowFiltering {
    public static func apply(_ windows: [SwitchableWindow], search: String = "", includeMinimized: Bool = true,
                             includeHidden: Bool = true, includeWindowless: Bool = true, currentApplication: Int32? = nil,
                             excludedBundlePaths: Set<String> = [], order: WindowSortOrder = .recent) -> [SwitchableWindow] {
        let values = windows.filter {
            (includeMinimized || !$0.minimized) && (includeHidden || !$0.hidden)
            && (includeWindowless || $0.windowAccessible)
            && (currentApplication == nil || $0.processID == currentApplication)
            && !excludedBundlePaths.contains($0.applicationURL?.path ?? "")
            && (search.isEmpty || "\($0.application) \($0.title)".localizedCaseInsensitiveContains(search))
        }
        // Stable ties preserve the server's application/window order.
        return values.enumerated().sorted { a, b in
            switch order {
            case .recent:
                let lhs = a.element.lastFocusedAt ?? .distantPast, rhs = b.element.lastFocusedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                if a.element.frontmost != b.element.frontmost { return a.element.frontmost }
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
}

public struct WindowCatalogReport: Sendable {
    public let windows: [SwitchableWindow]
    public let accessibilityGranted: Bool
    public let partial: Bool
}

public enum WindowAction: Sendable { case close, minimize, restore, toggleFullScreen, hideApplication }

public enum WindowCatalogError: Error, LocalizedError {
    case expired, focusFailed, unsupported, permissionRequired
    public var errorDescription: String? {
        switch self {
        case .expired: "Pencere ya da uygulama değişti. Listeyi yenile."
        case .focusFailed: "macOS işlemi tamamlayamadı. İzin veya Space durumunu kontrol et."
        case .unsupported: "Bu pencere bu işlemi desteklemiyor."
        case .permissionRequired: "Bu işlem için macOS Erişilebilirlik izni gerekiyor."
        }
    }
}

/// AX handles remain actor-isolated. Identity is revalidated before every mutation.
public actor WindowCatalog {
    private struct ApplicationInfo: Sendable {
        let pid: Int32
        let name: String
        let url: URL?
        let launchedAt: Date?
        let frontmost: Bool
        let hidden: Bool
    }
    private struct Handle { let application: ApplicationInfo; let window: AXUIElement? }
    private var handles: [String: Handle] = [:]
    private var focusHistory: [String: Date] = [:]
    private var applicationHistory: [Int32: Date] = [:]
    public init() {}

    public func noteApplicationActivation(_ pid: Int32) { if pid != getpid() { applicationHistory[pid] = Date() } }

    public func snapshot() async -> WindowCatalogReport {
        let apps = await MainActor.run {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }.map {
                ApplicationInfo(pid: $0.processIdentifier, name: $0.localizedName ?? "Uygulama", url: $0.bundleURL,
                                launchedAt: $0.launchDate, frontmost: $0.processIdentifier == front, hidden: $0.isHidden)
            }.sorted { $0.frontmost && !$1.frontmost }
        }
        let trusted = AXIsProcessTrusted()
        let deadline = Date().addingTimeInterval(8)
        var partial = false
        var values: [SwitchableWindow] = []
        var nextHandles: [String: Handle] = [:]
        for app in apps {
            if Task.isCancelled || Date() >= deadline || values.count >= 200 { partial = true; break }
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            var value: CFTypeRef?
            let elements: [AXUIElement]
            if trusted, AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] { elements = windows } else { elements = [] }
            let appKey = "\(app.pid)-\(app.launchedAt?.timeIntervalSince1970 ?? 0)"
            if elements.isEmpty {
                let id = "app-" + appKey
                nextHandles[id] = Handle(application: app, window: nil)
                values.append(.init(id: id, processID: app.pid, application: app.name,
                                    title: trusted ? "Listelenebilir pencere yok" : "Pencere erişimi bekleniyor",
                                    applicationURL: app.url, minimized: false, hidden: app.hidden, fullScreen: false,
                                    frontmost: app.frontmost, windowAccessible: false, canClose: false, canMinimize: false,
                                    canFullScreen: false, launchedAt: app.launchedAt, lastFocusedAt: applicationHistory[app.pid]))
            } else {
                var focused: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused)
                for window in elements.prefix(80) {
                    if Task.isCancelled || Date() >= deadline || values.count >= 200 { partial = true; break }
                    AXUIElementSetMessagingTimeout(window, 0.2)
                    let id = "window-\(appKey)-\(CFHash(window))"
                    let front = app.frontmost && focused.map { CFEqual($0, window) } == true
                    if front { focusHistory[id] = Date() }
                    let close = Self.elementAttribute(window, kAXCloseButtonAttribute)
                    let closable = close.map { (Self.attribute($0, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true } ?? false
                    nextHandles[id] = Handle(application: app, window: window)
                    values.append(.init(id: id, processID: app.pid, application: app.name,
                                        title: (Self.attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Başlıksız pencere",
                                        applicationURL: app.url, minimized: Self.boolean(window, kAXMinimizedAttribute), hidden: app.hidden,
                                        fullScreen: Self.boolean(window, "AXFullScreen"), frontmost: front, windowAccessible: true,
                                        canClose: closable, canMinimize: Self.settable(window, kAXMinimizedAttribute),
                                        canFullScreen: Self.settable(window, "AXFullScreen"), launchedAt: app.launchedAt,
                                        lastFocusedAt: focusHistory[id] ?? applicationHistory[app.pid]))
                }
                if elements.count > 80 { partial = true }
            }
            await Task.yield()
        }
        handles = nextHandles
        focusHistory = focusHistory.filter { nextHandles[$0.key] != nil }
        let livePIDs = Set(apps.map(\.pid)); applicationHistory = applicationHistory.filter { livePIDs.contains($0.key) }
        return .init(windows: values, accessibilityGranted: trusted, partial: partial)
    }

    public func focus(_ id: String) async throws {
        let handle = try await validatedHandle(id)
        let info = handle.application
        let activated = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: info.pid), app.launchDate == info.launchedAt else { return false }
            app.unhide(); return app.activate(options: [])
        }
        guard activated else { throw WindowCatalogError.expired }
        if let window = handle.window {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { throw WindowCatalogError.focusFailed }
        }
        focusHistory[id] = Date()
    }

    public func perform(_ action: WindowAction, on id: String) async throws {
        let handle = try await validatedHandle(id)
        if case .hideApplication = action {
            let info = handle.application
            let result = await MainActor.run { () -> Bool in
                guard let app = NSRunningApplication(processIdentifier: info.pid), app.launchDate == info.launchedAt else { return false }
                return app.hide()
            }
            guard result else { throw WindowCatalogError.focusFailed }; return
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
        case .hideApplication: return
        }
        guard result == .success else { throw WindowCatalogError.focusFailed }
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
