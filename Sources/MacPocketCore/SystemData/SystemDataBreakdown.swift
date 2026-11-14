import Foundation

public struct SystemDataBreakdownEntry: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let bytes: Int64
}

/// The biggest entries inside an item, so a decision can be made before anything is removed.
public enum SystemDataBreakdown {
    /// Measures the direct children of each folder and returns the `limit` largest. A file path is its own entry.
    public static func topEntries(of paths: [String], limit: Int = 5, maximumDuration: TimeInterval = 20) async -> [SystemDataBreakdownEntry] {
        let control = StorageScanControl(maximumDuration: maximumDuration, maximumEntries: 3_000_000)
        let links = HardLinkRegistry()
        return await StorageWork.run(control) {
            var entries: [SystemDataBreakdownEntry] = []
            for path in paths {
                var info = stat()
                guard lstat(path, &info) == 0 else { continue }
                let children: [String]
                if (info.st_mode & S_IFMT) == S_IFDIR {
                    children = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).map { path + "/" + $0 }
                } else {
                    children = [path]
                }
                for child in children {
                    var childInfo = stat()
                    guard lstat(child, &childInfo) == 0, (childInfo.st_mode & S_IFMT) != S_IFLNK else { continue }
                    let bytes: Int64
                    if (childInfo.st_mode & S_IFMT) == S_IFDIR {
                        bytes = DirectorySizer.measure(child, control: control, links: links).allocatedBytes
                    } else {
                        bytes = max(0, Int64(childInfo.st_blocks) * 512)
                    }
                    if bytes > 0 { entries.append(.init(name: (child as NSString).lastPathComponent, path: child, bytes: bytes)) }
                }
            }
            return Array(entries.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }.prefix(max(0, limit)))
        }
    }
}
