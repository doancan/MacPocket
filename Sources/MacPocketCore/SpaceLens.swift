import Darwin
import CoreGraphics
import Foundation

/// Broad type of a Space Lens node, used for color and icons.
public enum SpaceLensKind: String, Codable, Sendable, CaseIterable {
    case folder, package, image, video, audio, archive, document, code, diskImage, other, remainder

    public var title: String {
        switch self {
        case .folder: String(localized: "Klasör")
        case .package: String(localized: "Paket")
        case .image: String(localized: "Görsel")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Ses")
        case .archive: String(localized: "Arşiv")
        case .document: String(localized: "Belge")
        case .code: String(localized: "Kod ve veri")
        case .diskImage: String(localized: "Disk görüntüsü")
        case .other: String(localized: "Diğer dosya")
        case .remainder: String(localized: "Küçük öğeler")
        }
    }

    static func forFile(extension ext: String) -> SpaceLensKind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "raw", "cr2", "nef", "arw", "dng", "psd", "svg":
            .image
        case "mov", "mp4", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "3gp", "prproj", "braw":
            .video
        case "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "caf", "alac":
            .audio
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "xip", "pkg", "zst":
            .archive
        case "dmg", "iso", "img", "sparseimage", "sparsebundle", "vmdk", "qcow2", "vdi":
            .diskImage
        case "pdf", "doc", "docx", "pages", "key", "keynote", "numbers", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "epub":
            .document
        case "swift", "js", "ts", "json", "py", "rb", "go", "rs", "c", "h", "m", "cpp", "java", "kt", "sqlite", "db",
             "sqlite3", "log", "plist", "xml", "yml", "yaml", "csv", "o", "a", "dylib", "so", "jar", "wasm":
            .code
        default:
            .other
        }
    }
}

/// One node of the Space Lens tree. Children are retained only near the scanned root and only the
/// largest ones per folder; the rest are folded into a single `remainder` node so sizes still add up.
public struct SpaceLensNode: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let kind: SpaceLensKind
    public let allocatedBytes: Int64
    public let fileCount: Int
    /// lstat identity at scan time; nil for synthetic remainder nodes. Required to move an item to Trash.
    public let identity: FileIdentity?
    /// Retained children, largest first. Nil when the node is a file, a package, or deeper than the
    /// retained depth (drilling into such a folder triggers a new scan of that folder).
    public var children: [SpaceLensNode]?
    /// False when this subtree was not fully measured (budget, cancellation or unreadable items).
    public let complete: Bool
    public let inaccessibleCount: Int

    public var isDirectory: Bool { kind == .folder }
    public var url: URL { URL(fileURLWithPath: path) }
    /// True for a folder whose children have not been loaded yet.
    public var needsExpansion: Bool { kind == .folder && children == nil }

    /// Finds a descendant by path (or self).
    public func node(at target: String) -> SpaceLensNode? {
        if target == path { return self }
        guard target.hasPrefix(path == "/" ? "/" : path + "/"), let children else { return nil }
        for child in children where child.kind != .remainder {
            if let found = child.node(at: target) { return found }
        }
        return nil
    }

    /// Returns a copy where the node at `target` is replaced (used to graft a deeper scan).
    public func replacing(_ target: String, with replacement: SpaceLensNode) -> SpaceLensNode {
        if target == path { return replacement }
        guard target.hasPrefix(path == "/" ? "/" : path + "/"), let children else { return self }
        var copy = self
        copy.children = children.map { $0.replacing(target, with: replacement) }
        return copy
    }

    /// Returns a copy without the given paths; sizes of every ancestor shrink accordingly.
    public func removing(_ paths: Set<String>) -> SpaceLensNode {
        guard let children, !paths.isEmpty else { return self }
        var removedBytes: Int64 = 0
        var removedFiles = 0
        var kept: [SpaceLensNode] = []
        for child in children {
            if paths.contains(child.path) {
                removedBytes += child.allocatedBytes; removedFiles += child.fileCount
                continue
            }
            let updated = child.removing(paths)
            removedBytes += child.allocatedBytes - updated.allocatedBytes
            removedFiles += child.fileCount - updated.fileCount
            kept.append(updated)
        }
        kept.sort { $0.allocatedBytes > $1.allocatedBytes }
        return SpaceLensNode(path: path, name: name, kind: kind, allocatedBytes: max(0, allocatedBytes - removedBytes),
                             fileCount: max(0, fileCount - removedFiles), identity: identity, children: kept,
                             complete: complete, inaccessibleCount: inaccessibleCount)
    }
}

public struct SpaceLensOptions: Sendable {
    /// Levels below the root whose children are kept in memory.
    public var retainedDepth = 3
    /// Children kept per folder; the rest become one remainder node.
    public var childrenPerFolder = 150
    /// Upper bound on retained nodes for the whole tree.
    public var maximumRetainedNodes = 80_000
    public init() {}
}

public struct SpaceLensReport: Sendable {
    public let root: SpaceLensNode
    public let scannedAt: Date
    public let duration: TimeInterval
    public let visitedEntries: Int
    public let limitReached: Bool
}

/// Builds the Space Lens tree: symlinks are not followed, other volumes are skipped, hard links count once.
public struct SpaceLensScanner: Sendable {
    public init() {}

    /// Top-level folders are walked in parallel (each on its own GCD thread) and assembled afterwards.
    public func scan(_ root: URL, options: SpaceLensOptions = .init(), control: StorageScanControl,
                     concurrency: Int = 6) async throws -> SpaceLensReport {
        let canonical = try canonicalFileURL(root.standardizedFileURL)
        let rootIdentity = try FileIdentity.read(canonical)
        guard rootIdentity.isDirectory else { throw FileServiceError.notDirectory }
        let started = Date()
        let rootPath = canonical.path
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: rootPath) } catch { throw FileServiceError.unreadable }
        let shared = SpaceLensAssembly(options: options, control: control)
        let assembler = SpaceLensAssembler(shared: shared)
        let top = SpaceLensAssembler.Builder(path: rootPath, level: 0, identity: rootIdentity, isPackage: false,
                                             retainsChildren: options.retainedDepth > 0, bytes: allocatedSize(rootPath))
        var subtrees: [String] = []
        for name in names.sorted() {
            let path = rootPath == "/" ? "/" + name : rootPath + "/" + name
            guard let identity = lstatIdentity(path) else { top.inaccessible += 1; top.complete = false; continue }
            if identity.isSymbolicLink || identity.device != rootIdentity.device { continue }
            if identity.isDirectory { subtrees.append(path); continue }
            guard identity.isRegularFile else { continue }
            if identity.links > 1, !shared.links.insert(device: identity.device, inode: identity.inode) { continue }
            assembler.append(SpaceLensNode(path: path, name: name, kind: .forFile(extension: (name as NSString).pathExtension),
                                           allocatedBytes: allocatedSize(path), fileCount: 1, identity: identity, children: nil,
                                           complete: true, inaccessibleCount: 0), to: top)
        }
        let retainsTop = top.retainsChildren
        var nodes: [SpaceLensNode] = []
        var unreadable = 0
        await withTaskGroup(of: SpaceLensNode?.self) { group in
            var pending = subtrees[...]
            func launch() {
                guard let path = pending.popFirst() else { return }
                group.addTask {
                    await StorageWork.run(control) {
                        SpaceLensAssembler(shared: shared).walk(path, levelOffset: 1, parentRetains: retainsTop)
                    }
                }
            }
            for _ in 0..<max(1, concurrency) { launch() }
            while let node = await group.next() {
                if let node { nodes.append(node) } else { unreadable += 1 }
                launch()
            }
        }
        if control.isCancelled { throw CancellationError() }
        if unreadable > 0 { top.inaccessible += unreadable; top.complete = false }
        for node in nodes { assembler.append(node, to: top) }
        if control.limitReached { top.complete = false }
        let tree = assembler.finish(top, stopped: false)
        return SpaceLensReport(root: tree, scannedAt: started, duration: Date().timeIntervalSince(started),
                               visitedEntries: control.snapshot.visitedEntries, limitReached: control.limitReached)
    }

    /// Single-threaded build of a whole tree.
    static func build(_ rootPath: String, options: SpaceLensOptions, control: StorageScanControl) -> SpaceLensNode? {
        SpaceLensAssembler(shared: SpaceLensAssembly(options: options, control: control))
            .walk(rootPath, levelOffset: 0, parentRetains: false)
    }
}

private func allocatedSize(_ path: String) -> Int64 {
    var info = stat()
    guard lstat(path, &info) == 0 else { return 0 }
    return max(0, Int64(info.st_blocks) * 512)
}

/// State shared by the parallel walkers of one Space Lens scan.
final class SpaceLensAssembly: @unchecked Sendable {
    let options: SpaceLensOptions
    let control: StorageScanControl
    let links = HardLinkRegistry()
    private let lock = NSLock()
    private var retained = 0

    init(options: SpaceLensOptions, control: StorageScanControl) { self.options = options; self.control = control }

    /// Reserves room for one more retained node; false once the tree-wide limit is reached.
    func reserve() -> Bool {
        lock.withLock {
            guard retained < options.maximumRetainedNodes else { return false }
            retained += 1
            return true
        }
    }

    func release(_ count: Int) { lock.withLock { retained = max(0, retained - count) } }
    var retainedCount: Int { lock.withLock { retained } }
}

/// Builds Space Lens nodes from fts walks: sizes roll up post-order, children are retained near the
/// scan root only, and wide folders keep their largest children and fold the rest into a remainder node.
struct SpaceLensAssembler {
    let shared: SpaceLensAssembly

    final class Builder {
        let path: String
        let level: Int
        let identity: FileIdentity?
        let isPackage: Bool
        let retainsChildren: Bool
        var bytes: Int64
        var files = 0
        var inaccessible = 0
        var complete = true
        var children: [SpaceLensNode] = []
        var foldedBytes: Int64 = 0
        var foldedFiles = 0
        var foldedCount = 0

        init(path: String, level: Int, identity: FileIdentity?, isPackage: Bool, retainsChildren: Bool, bytes: Int64) {
            self.path = path; self.level = level; self.identity = identity; self.isPackage = isPackage
            self.retainsChildren = retainsChildren; self.bytes = bytes
        }
    }

    private var perFolder: Int { max(1, shared.options.childrenPerFolder) }

    func append(_ node: SpaceLensNode, to parent: Builder) {
        parent.bytes += node.allocatedBytes
        parent.files += node.fileCount
        parent.inaccessible += node.inaccessibleCount
        if !node.complete { parent.complete = false }
        guard parent.retainsChildren, shared.reserve() else {
            parent.foldedBytes += node.allocatedBytes; parent.foldedFiles += node.fileCount; parent.foldedCount += 1
            shared.release(Self.descendantCount(node))
            return
        }
        parent.children.append(node)
        // Keep memory bounded in very wide folders: fold the smallest beyond twice the limit.
        if parent.children.count > perFolder * 2 { fold(parent) }
    }

    private func fold(_ builder: Builder) {
        builder.children.sort { $0.allocatedBytes > $1.allocatedBytes }
        guard builder.children.count > perFolder else { return }
        var released = 0
        for node in builder.children[perFolder...] {
            builder.foldedBytes += node.allocatedBytes; builder.foldedFiles += node.fileCount; builder.foldedCount += 1
            released += 1 + Self.descendantCount(node)
        }
        builder.children.removeLast(builder.children.count - perFolder)
        shared.release(released)
    }

    static func descendantCount(_ node: SpaceLensNode) -> Int {
        (node.children ?? []).reduce(0) { $0 + 1 + descendantCount($1) }
    }

    func finish(_ builder: Builder, stopped: Bool) -> SpaceLensNode {
        var children: [SpaceLensNode]?
        if builder.retainsChildren {
            fold(builder)
            var list = builder.children
            if builder.foldedCount > 0 {
                list.append(SpaceLensNode(path: builder.path + "/\u{0}remainder", name: String(localized: "\(builder.foldedCount) küçük öğe"),
                                          kind: .remainder, allocatedBytes: builder.foldedBytes, fileCount: builder.foldedFiles,
                                          identity: nil, children: nil, complete: true, inaccessibleCount: 0))
            }
            list.sort { $0.allocatedBytes > $1.allocatedBytes }
            children = list
        }
        return SpaceLensNode(path: builder.path, name: builder.path == "/" ? "/" : (builder.path as NSString).lastPathComponent,
                             kind: builder.isPackage ? .package : .folder, allocatedBytes: builder.bytes,
                             fileCount: builder.files, identity: builder.identity,
                             children: builder.isPackage ? nil : children,
                             complete: builder.complete && !stopped, inaccessibleCount: builder.inaccessible)
    }

    /// Walks `rootPath`, whose depth below the Space Lens root is `levelOffset`. Nil when it cannot be read.
    func walk(_ rootPath: String, levelOffset: Int, parentRetains: Bool) -> SpaceLensNode? {
        let options = shared.options
        let control = shared.control
        var stack: [Builder] = []
        var result: SpaceLensNode?
        var pendingEntries = 0
        var pendingBytes: Int64 = 0
        var stopped = false

        let started = TreeWalker.walk(rootPath) { entry in
            pendingEntries += 1
            pendingBytes += entry.kind == .file ? entry.allocatedBytes : 0
            if pendingEntries >= DirectorySizer.batch {
                let keepGoing = control.record(entries: pendingEntries, bytes: pendingBytes)
                pendingEntries = 0; pendingBytes = 0
                if !keepGoing { stopped = true; return .stop }
            }
            let level = entry.level + levelOffset
            switch entry.kind {
            case .directory:
                let parent = stack.last
                let parentRetainsChildren = parent?.retainsChildren ?? parentRetains
                // Package detection costs a LaunchServices lookup, so it only runs where the result is shown.
                let isPackage = level > 0 && (parent?.isPackage == true
                    || (parentRetainsChildren && FileScanner.isPackage(URL(fileURLWithPath: entry.path))))
                let retains = !isPackage && level < options.retainedDepth
                // Only shown nodes (which may be offered for Trash) need an exact identity; fts's stat
                // lacks the nanoseconds FileTrashRequest compares, so it is read again with lstat.
                let needsIdentity = level == 0 || parentRetainsChildren
                stack.append(Builder(path: entry.path, level: level, identity: needsIdentity ? lstatIdentity(entry.path) : nil,
                                     isPackage: isPackage, retainsChildren: retains, bytes: entry.allocatedBytes))
            case .directoryPost:
                guard let builder = stack.popLast() else { break }
                let node = finish(builder, stopped: false)
                if let parent = stack.last { append(node, to: parent) } else { result = node }
            case .file:
                if entry.links > 1, !shared.links.insert(device: entry.device, inode: entry.inode) { return .proceed }
                guard let parent = stack.last else {
                    // The walk root itself is a file.
                    let name = (entry.path as NSString).lastPathComponent
                    result = SpaceLensNode(path: entry.path, name: name, kind: .forFile(extension: (name as NSString).pathExtension),
                                           allocatedBytes: entry.allocatedBytes, fileCount: 1, identity: lstatIdentity(entry.path),
                                           children: nil, complete: true, inaccessibleCount: 0)
                    break
                }
                if parent.retainsChildren {
                    let name = (entry.path as NSString).lastPathComponent
                    append(SpaceLensNode(path: entry.path, name: name, kind: .forFile(extension: (name as NSString).pathExtension),
                                         allocatedBytes: entry.allocatedBytes, fileCount: 1, identity: lstatIdentity(entry.path),
                                         children: nil, complete: true, inaccessibleCount: 0), to: parent)
                } else {
                    parent.bytes += entry.allocatedBytes
                    parent.files += 1
                }
            case .symlink, .other:
                break  // Never followed; the link itself is not counted.
            case .unreadable:
                // fts reports a directory it cannot open as FTS_D followed by FTS_DNR/FTS_ERR instead of
                // FTS_DP, so an error for the open directory itself closes it.
                if let open = stack.last, open.path == entry.path {
                    stack.removeLast()
                    open.inaccessible += 1
                    open.complete = false
                    let node = finish(open, stopped: false)
                    if let parent = stack.last { append(node, to: parent) } else { result = node }
                } else if let parent = stack.last {
                    parent.inaccessible += 1
                    parent.complete = false
                }
            }
            return .proceed
        }
        guard started else { return nil }
        if !stopped { _ = control.record(entries: pendingEntries, bytes: pendingBytes) }
        // A stopped walk leaves folders open: close them bottom-up so partial sizes still roll up.
        while let builder = stack.popLast() {
            builder.complete = false
            let node = finish(builder, stopped: true)
            if let parent = stack.last { append(node, to: parent) } else { result = node }
        }
        return result
    }
}

// MARK: - Treemap

/// Squarified treemap (Bruls, Huizing, van Wijk). Pure geometry so it can be unit tested.
public enum Treemap {
    /// Returns one rectangle per value, in the input order. Values must be non-negative; zero values get
    /// an empty rectangle. Rectangles tile `bounds` exactly (up to floating point) and never overlap.
    public static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }
        let scale = Double(bounds.width * bounds.height) / total
        // Largest first gives the best aspect ratios; keep original indices.
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        var remaining = bounds
        var row: [Int] = []
        var index = 0

        func areas(_ indices: [Int]) -> [Double] { indices.map { values[$0] * scale } }
        func worst(_ rowAreas: [Double], side: Double) -> Double {
            let sum = rowAreas.reduce(0, +)
            guard let maximum = rowAreas.max(), let minimum = rowAreas.min(), minimum > 0, sum > 0 else { return .infinity }
            let side2 = side * side, sum2 = sum * sum
            return max(side2 * maximum / sum2, sum2 / (side2 * minimum))
        }
        func place(_ indices: [Int], isLast: Bool) {
            let rowAreas = areas(indices)
            let sum = rowAreas.reduce(0, +)
            let horizontal = remaining.width >= remaining.height  // lay the row along the short side
            if horizontal {
                // Column on the left; its width is the row's area divided by the height.
                let width = isLast ? remaining.width : CGFloat(sum / Double(remaining.height))
                var y = remaining.minY
                for (offset, item) in indices.enumerated() {
                    let height = offset == indices.count - 1 ? remaining.maxY - y : CGFloat(rowAreas[offset] / Double(width))
                    result[item] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(0, remaining.width - width), height: remaining.height)
            } else {
                let height = isLast ? remaining.height : CGFloat(sum / Double(remaining.width))
                var x = remaining.minX
                for (offset, item) in indices.enumerated() {
                    let width = offset == indices.count - 1 ? remaining.maxX - x : CGFloat(rowAreas[offset] / Double(height))
                    result[item] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(0, remaining.height - height))
            }
        }

        while index < order.count {
            let item = order[index]
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(areas(row + [item]), side: side) <= worst(areas(row), side: side) {
                row.append(item)
                index += 1
            } else {
                place(row, isLast: false)
                row = []
            }
        }
        if !row.isEmpty { place(row, isLast: true) }
        return result
    }
}
