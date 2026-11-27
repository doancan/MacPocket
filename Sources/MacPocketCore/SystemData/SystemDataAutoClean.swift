import Foundation

/// The one thing MacPocket may do without being asked item by item: remove Safe items. Drawn as narrowly as
/// the confirmation dialog allows: nothing marked Review, nothing that needs an administrator password,
/// nothing whose owning app is open, and never an item whose size is unknown.
public enum SystemDataAutoClean {
    public static func eligible(_ items: [SystemDataItem], runningBundleIDs: Set<String> = [],
                                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> [SystemDataItem] {
        items.filter { item in
            guard item.safety == .safe, item.isRemovable, item.sizeKnown, item.sizeBytes > 0,
                  item.group != .trash, item.busyBundleIDs.allSatisfy({ !runningBundleIDs.contains($0) }) else { return false }
            let preview = SystemDataRemovalPlanner.preview(items: [item], mode: .deletePermanently, home: home, temporaryDirectory: temporaryDirectory)
            return !(preview.lines.first?.requiresAdministrator ?? true)
        }
    }

    /// A weekly clean is due once seven days have passed since the last one (or there never was one).
    public static func isDue(lastRun: Date?, now: Date = Date()) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= 7 * 86_400
    }
}
