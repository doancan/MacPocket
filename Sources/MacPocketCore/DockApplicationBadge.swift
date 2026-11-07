import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// The Dock badge belongs to the application tile, not to an individual window or native tab.
public struct DockApplicationBadge: Hashable, Sendable {
    public let label: String
    public init?(_ value: String?) {
        guard let value,value.utf16.count <= 256 else { return nil }
        let cleaned = value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !cleaned.isEmpty,!cleaned.unicodeScalars.contains(where: {
            (CharacterSet.controlCharacters.contains($0) && $0.value != 0x200C && $0.value != 0x200D) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
        }) else { return nil }
        label = cleaned
    }
    public var displayText: String { label.count <= 4 ? label : String(label.prefix(3)) + "…" }
    public var localizedDescription: String { String(localized: "Uygulamanın Dock rozeti: \(label)") }
}

/// Process launch time prevents a late badge read from attaching to a replacement process.
public struct DockBadgeTarget: Hashable, Sendable {
    public let processID: Int32
    public let launchedAt: Date
    public let applicationURL: URL
    public init?(processID: Int32,launchedAt: Date?,applicationURL: URL?) {
        guard processID > 0,let launchedAt,launchedAt.timeIntervalSince1970.isFinite,
              let applicationURL,let url = Self.applicationURL(applicationURL) else { return nil }
        self.processID = processID;self.launchedAt = launchedAt;self.applicationURL = url
    }
    public init?(_ window: SwitchableWindow) { self.init(processID: window.processID,launchedAt: window.launchedAt,applicationURL: window.applicationURL) }
    public static func applicationURL(_ url: URL) -> URL? {
        guard url.isFileURL,url.host == nil || url.host == "" || url.host == "localhost",
              url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return nil }
        return url.standardizedFileURL
    }
}

public protocol DockApplicationBadgeReading: Sendable {
    func badges(for targets: [DockBadgeTarget]) async -> [DockBadgeTarget: DockApplicationBadge]
}

/// Duplicate Dock tiles with conflicting labels (including a missing label) are ambiguous.
/// Keep complete snapshots: absence always removes an old badge, rather than inventing a count.
public enum DockBadgeMapping {
    public static func labels(_ tiles: [(url: URL,label: String?)]) -> [URL: DockApplicationBadge] {
        let groups = Dictionary(grouping: tiles.compactMap { tile -> (URL,DockApplicationBadge?)? in
            guard let url = DockBadgeTarget.applicationURL(tile.url) else { return nil }
            return (url,DockApplicationBadge(tile.label))
        },by: { $0.0 })
        return groups.compactMapValues { values in
            let distinct = Set(values.map { $0.1 })
            guard distinct.count == 1 else { return nil }
            return distinct.first ?? nil
        }
    }
}

/// Bounded, passive AX reads off main. No Dock actions, notification database, observers, permission
/// prompts or cached AX elements. A restarted Dock is rediscovered on the next visible-panel poll.
public actor DockApplicationBadgeReader: DockApplicationBadgeReading {
    public init() {}
    public func badges(for targets: [DockBadgeTarget]) async -> [DockBadgeTarget: DockApplicationBadge] {
        let requested = Set(targets)
        guard !requested.isEmpty,requested.count <= 256,AXIsProcessTrusted(),!Task.isCancelled else { return [:] }
        let (dockIdentity,initial) = await MainActor.run {
            let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").filter { !$0.isTerminated }
            let dock = candidates.count == 1 ? candidates.first : nil
            let identity = dock.flatMap { app -> DockBadgeTarget? in
                guard !app.isTerminated else { return nil }
                return .init(processID: app.processIdentifier,launchedAt: CatalogWindowIdentity.processLaunchDate(pid: app.processIdentifier,applicationDate: app.launchDate),applicationURL: app.bundleURL)
            }
            return (identity,Self.runningTargets(requested))
        }
        guard let dockIdentity,!Task.isCancelled else { return [:] }
        func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }
        func matches(_ target: DockBadgeTarget,_ running: Set<DockBadgeTarget>) -> Bool {
            running.contains { $0.processID == target.processID && $0.launchedAt == target.launchedAt && canonical($0.applicationURL) == canonical(target.applicationURL) }
        }
        let valid = requested.filter { matches($0,initial) }
        guard !valid.isEmpty else { return [:] }
        let wantedURLs = Set(valid.map { canonical($0.applicationURL) })
        let deadline = ContinuousClock.now + .milliseconds(250)
        let dock = AXUIElementCreateApplication(dockIdentity.processID)
        guard let roots = children(dock,limit: 32,deadline: deadline) else { return [:] }
        var list: AXUIElement?
        for root in roots {
            guard canRead(deadline) else { return [:] }
            if attribute(root,kAXRoleAttribute,deadline: deadline) as? String == kAXListRole as String { list = root;break }
        }
        guard let list,let items = children(list,limit: 512,deadline: deadline) else { return [:] }
        var tiles: [(url: URL,label: String?)] = []
        for item in items {
            guard canRead(deadline) else { return [:] }
            AXUIElementSetMessagingTimeout(item,0.025)
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item,[kAXSubroleAttribute,kAXURLAttribute,kAXIsApplicationRunningAttribute] as CFArray,[],&values) == .success,
                  let data = values as? [Any],data.count == 3,data[0] as? String == kAXApplicationDockItemSubrole as String,
                  (data[2] as? NSNumber)?.boolValue == true else { continue }
            let rawURL = (data[1] as? URL) ?? (data[1] as? String).flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0) }
            guard let rawURL,let appURL = DockBadgeTarget.applicationURL(rawURL) else { continue }
            let url = canonical(appURL)
            guard wantedURLs.contains(url) else { continue } // Never read unrequested app labels.
            let label = attribute(item,"AXStatusLabel",deadline: deadline) as? String
            tiles.append((url,label))
        }
        guard canRead(deadline),AXIsProcessTrusted() else { return [:] }
        let (sameDock,current) = await MainActor.run {
            let app = NSRunningApplication(processIdentifier: dockIdentity.processID)
            let same = app?.bundleIdentifier == "com.apple.dock" && app?.isTerminated == false
                && CatalogWindowIdentity.processLaunchDate(pid: dockIdentity.processID,applicationDate: app?.launchDate) == dockIdentity.launchedAt
            return (same,Self.runningTargets(requested))
        }
        guard sameDock,!Task.isCancelled else { return [:] }
        let labels = DockBadgeMapping.labels(tiles)
        return Dictionary(uniqueKeysWithValues: valid.compactMap { target in
            guard matches(target,current),let badge = labels[canonical(target.applicationURL)] else { return nil }
            return (target,badge)
        })
    }
    @MainActor private static func runningTargets(_ requested: Set<DockBadgeTarget>) -> Set<DockBadgeTarget> {
        Set(requested.compactMap { target in
            guard let app = NSRunningApplication(processIdentifier: target.processID),!app.isTerminated else { return nil }
            return DockBadgeTarget(processID: app.processIdentifier,launchedAt: CatalogWindowIdentity.processLaunchDate(pid: app.processIdentifier,applicationDate: app.launchDate),applicationURL: app.bundleURL)
        })
    }
    private func canRead(_ deadline: ContinuousClock.Instant) -> Bool { !Task.isCancelled && ContinuousClock.now < deadline }
    private func attribute(_ element: AXUIElement,_ name: String,deadline: ContinuousClock.Instant) -> CFTypeRef? {
        guard canRead(deadline) else { return nil }
        AXUIElementSetMessagingTimeout(element,0.025)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
    }
    private func children(_ element: AXUIElement,limit: Int,deadline: ContinuousClock.Instant) -> [AXUIElement]? {
        guard canRead(deadline) else { return nil }
        AXUIElementSetMessagingTimeout(element,0.025)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element,kAXChildrenAttribute as CFString,&count) == .success,(0...limit).contains(count),canRead(deadline) else { return nil }
        if count == 0 { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(element,kAXChildrenAttribute as CFString,0,count,&values) == .success,
              let result = values as? [AXUIElement],result.count == count else { return nil }
        return result
    }
}
