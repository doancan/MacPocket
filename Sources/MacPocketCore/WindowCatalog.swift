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
    public let windowAccessible: Bool
}

public struct WindowCatalogReport: Sendable {
    public let windows: [SwitchableWindow]
    public let accessibilityGranted: Bool
    public let partial: Bool
}

public enum WindowCatalogError: Error, LocalizedError {
    case expired, focusFailed
    public var errorDescription: String? {
        switch self {
        case .expired: "Pencere ya da uygulama değişti. Listeyi yenile."
        case .focusFailed: "macOS pencereyi öne getiremedi. İzin veya Space durumunu kontrol et."
        }
    }
}

/// AX handles stay actor-isolated; only value descriptions cross to the UI.
public actor WindowCatalog {
    private struct ApplicationInfo: Sendable {
        let pid: Int32
        let name: String
        let url: URL?
        let launchedAt: Date?
        let frontmost: Bool
    }
    private struct Handle {
        let application: ApplicationInfo
        let window: AXUIElement?
    }
    private var handles: [String: Handle] = [:]
    public init() {}

    public func snapshot() async -> WindowCatalogReport {
        let apps = await MainActor.run {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }.map {
                ApplicationInfo(pid: $0.processIdentifier, name: $0.localizedName ?? "Uygulama", url: $0.bundleURL,
                                launchedAt: $0.launchDate, frontmost: $0.processIdentifier == front)
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
               let windows = value as? [AXUIElement] { elements = windows }
            else { elements = [] }
            if elements.isEmpty {
                let id = UUID().uuidString
                nextHandles[id] = Handle(application: app, window: nil)
                values.append(.init(id: id, processID: app.pid, application: app.name,
                                    title: trusted ? "Listelenebilir pencere yok" : "Pencere erişimi bekleniyor",
                                    applicationURL: app.url, minimized: false, windowAccessible: false))
            } else {
                for window in elements.prefix(80) {
                    if Task.isCancelled || Date() >= deadline || values.count >= 200 { partial = true; break }
                    AXUIElementSetMessagingTimeout(window, 0.2)
                    var titleValue: CFTypeRef?, minimizedValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                    let id = UUID().uuidString
                    nextHandles[id] = Handle(application: app, window: window)
                    values.append(.init(id: id, processID: app.pid, application: app.name,
                                        title: (titleValue as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Başlıksız pencere",
                                        applicationURL: app.url, minimized: (minimizedValue as? NSNumber)?.boolValue ?? false, windowAccessible: true))
                }
                if elements.count > 80 { partial = true }
            }
            await Task.yield()
        }
        handles = nextHandles
        return .init(windows: values, accessibilityGranted: trusted, partial: partial)
    }

    public func focus(_ id: String) async throws {
        guard let handle = handles[id] else { throw WindowCatalogError.expired }
        let info = handle.application
        let activated = await MainActor.run {
            guard let app = NSRunningApplication(processIdentifier: info.pid),
                  app.launchDate == info.launchedAt else { return false }
            app.unhide()
            return app.activate(options: [])
        }
        guard activated else { throw WindowCatalogError.expired }
        if let window = handle.window {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { throw WindowCatalogError.focusFailed }
        }
    }

    @MainActor public static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}
