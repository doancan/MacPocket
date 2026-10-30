import CoreGraphics
import Foundation

/// A named arrangement of windows to put back with one shortcut.
public struct SavedWindow: Codable, Hashable, Sendable {
    public let bundleID: String
    public let title: String
    /// Accessibility coordinates (top-left origin of the primary display).
    public let frame: CGRect

    public init(bundleID: String, title: String, frame: CGRect) {
        self.bundleID = bundleID; self.title = title; self.frame = frame
    }
}

public struct WorkspaceLayout: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var windows: [SavedWindow]
    public var shortcut: KeyCombo?
    /// Open apps that aren't running when the layout is restored.
    public var launchMissingApps = true
    public var savedAt: Date

    public init(id: UUID = UUID(), name: String, windows: [SavedWindow], shortcut: KeyCombo? = nil, launchMissingApps: Bool = true,
                savedAt: Date) {
        self.id = id; self.name = name; self.windows = windows; self.shortcut = shortcut
        self.launchMissingApps = launchMissingApps; self.savedAt = savedAt
    }

    public var applications: [String] {
        var seen = Set<String>()
        return windows.map(\.bundleID).filter { seen.insert($0).inserted }
    }
}

public enum WorkspaceMatcher {
    /// Pairs saved windows of one app with its current windows (by index into `current` titles): the same title
    /// first, then the remaining ones in order. Extra windows on either side are left alone.
    public static func match(saved: [SavedWindow], currentTitles: [String]) -> [(saved: SavedWindow, index: Int)] {
        var free = Array(currentTitles.indices)
        var pairs: [(SavedWindow, Int)] = []
        var leftover: [SavedWindow] = []
        for window in saved {
            if !window.title.isEmpty, let position = free.firstIndex(where: { currentTitles[$0] == window.title }) {
                pairs.append((window, free.remove(at: position)))
            } else {
                leftover.append(window)
            }
        }
        for window in leftover where !free.isEmpty {
            pairs.append((window, free.removeFirst()))
        }
        return pairs
    }

    /// A frame that is at least partly on a screen (some pixels of the title bar), so a layout saved with a
    /// display that's now gone never puts a window out of reach.
    public static func isReachable(_ frame: CGRect, screens: [CGRect]) -> Bool {
        let titleBar = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(30, frame.height))
        return screens.contains { $0.intersection(titleBar).width >= 40 }
    }
}

public struct WorkspaceStore: Codable, Equatable, Sendable {
    public var layouts: [WorkspaceLayout] = []
    public static let storageKey = "MacPocket.workspaces"

    public init(layouts: [WorkspaceLayout] = []) { self.layouts = layouts }

    public static func load(from defaults: UserDefaults) -> WorkspaceStore {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(WorkspaceStore.self, from: $0) } ?? WorkspaceStore()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}
