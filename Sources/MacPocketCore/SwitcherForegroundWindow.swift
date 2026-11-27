import AppKit
@preconcurrency import ApplicationServices
import Foundation

public struct SwitcherForegroundApplication: Hashable, Sendable {
    public let processID: Int32
    public let launchedAt: Date?
    public let bundleIdentifier: String?
    public let applicationPath: String?
    public let name: String?
    public init(processID: Int32, launchedAt: Date?, bundleIdentifier: String?, applicationPath: String?, name: String? = nil) {
        self.processID = processID
        self.launchedAt = launchedAt
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.name = name
    }
    @MainActor public init(_ app: NSRunningApplication) {
        name = app.localizedName
        processID = app.processIdentifier
        launchedAt = CatalogWindowIdentity.processLaunchDate(pid: app.processIdentifier, applicationDate: app.launchDate)
        bundleIdentifier = app.bundleIdentifier
        applicationPath = app.bundleURL?.path
    }
}

/// A focused-window-only read, used only while a conditional shortcut rule matches the
/// foreground application. No catalog scan, input monitoring or permission prompts.
public actor SwitcherForegroundWindowReader {
    public static let shared = SwitcherForegroundWindowReader()
    public func isFullscreen(_ application: SwitcherForegroundApplication) async -> Bool? {
        guard !Task.isCancelled, AXIsProcessTrusted(), let launch = application.launchedAt,
              CatalogWindowIdentity.processLaunchDate(pid: application.processID, applicationDate: nil) == launch else { return nil }
        let app = AXUIElementCreateApplication(application.processID)
        AXUIElementSetMessagingTimeout(app, 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(), !Task.isCancelled else { return nil }
        let window = unsafeDowncast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.03)
        var pid: pid_t = 0, flag: CFTypeRef?
        guard AXUIElementGetPid(window, &pid) == .success, pid == application.processID,
              AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &flag) == .success,
              let flag, CFGetTypeID(flag) == CFBooleanGetTypeID(), !Task.isCancelled,
              CatalogWindowIdentity.processLaunchDate(pid: application.processID, applicationDate: nil) == launch else { return nil }
        return CFBooleanGetValue(unsafeDowncast(flag, to: CFBoolean.self))
    }
}
