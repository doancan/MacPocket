import AppKit
@preconcurrency import ApplicationServices
import Foundation

public struct DockHoverItem: Equatable, Sendable {
    public let applicationURL: URL
    public let application: String
    public let processIDs: Set<Int32>
    public let iconFrame: CGRect
    public init(applicationURL: URL, application: String, processIDs: Set<Int32>, iconFrame: CGRect) {
        self.applicationURL = applicationURL
        self.application = application
        self.processIDs = processIDs
        self.iconFrame = iconFrame
    }
}

/// Passive Dock hit testing, isolated from the main thread. No interception of Dock clicks or preference
/// writes.
public actor DockItemResolver {
    private var dock: AXUIElement?
    private var dockPID: Int32?
    private var cachedURL: URL?
    private var cachedApps: (name: String, pids: Set<Int32>)?
    private var appsReadAt = Date.distantPast
    public init() {}

    public func item(at point: CGPoint, primaryHeight: CGFloat) async -> DockHoverItem? {
        guard AXIsProcessTrusted(), !Task.isCancelled else { return nil }
        if dock == nil {
            let pid = await MainActor.run { NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier }
            guard let pid else { return nil }
            dockPID = pid
            dock = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(dock!, 0.08)
        }
        guard let dock else { return nil }
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(primaryHeight - point.y), &hit)
        if status == .invalidUIElement { self.dock = nil; dockPID = nil; return nil }
        guard status == .success, var item = hit else { return nil }
        for _ in 0..<7 {
            guard !Task.isCancelled else { return nil }
            let subrole = attribute(item, kAXSubroleAttribute) as? String
            if subrole == "AXApplicationDockItem" {
                guard let position = attribute(item, kAXPositionAttribute), let size = attribute(item, kAXSizeAttribute),
                      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
                var origin = CGPoint.zero, extent = CGSize.zero
                guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
                      AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent),
                      extent.width > 0, extent.height > 0 else { return nil }
                let frame = CGRect(x: origin.x, y: primaryHeight - origin.y - extent.height, width: extent.width, height: extent.height)
                let rawURL = attribute(item, kAXURLAttribute)
                let url = (rawURL as? URL) ?? (rawURL as? String).flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0) }
                guard let url, url.isFileURL, url.pathExtension.lowercased() == "app" else { return nil }
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
                if cachedURL != canonical || Date().timeIntervalSince(appsReadAt) > 0.8 {
                    let running = await MainActor.run {
                        NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map {
                            (pid: $0.processIdentifier, url: $0.bundleURL, name: $0.localizedName)
                        }
                    }
                    let apps = running.filter { $0.url?.standardizedFileURL.resolvingSymlinksInPath() == canonical }
                    cachedApps = (apps.first?.name ?? canonical.deletingPathExtension().lastPathComponent, Set(apps.map { $0.pid }))
                    cachedURL = canonical
                    appsReadAt = Date()
                }
                guard let apps = cachedApps, !apps.pids.isEmpty else { return nil }
                return DockHoverItem(applicationURL: canonical, application: apps.name, processIDs: apps.pids, iconFrame: frame)
            }
            guard let parent = attribute(item, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            item = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
