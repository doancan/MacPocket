import Foundation
import CoreFoundation

/// A bookmark follows a renamed file; identity prevents a replacement at the old path being used accidentally.
public struct ShelfFileReference: Codable, Equatable, Sendable {
    public let originalURL: URL
    public let bookmark: Data?
    public let device: Int32
    public let inode: UInt64
    private let referenceURLString: String?

    public init(url: URL) throws {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let identity = try FileIdentity.read(url)
        originalURL = url
        device = identity.device
        inode = identity.inode
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: [.fileResourceIdentifierKey], relativeTo: nil)
        // Swift's URL bridge converts file-reference URLs into paths. Keep the CF URL's string instead.
        referenceURLString = CFURLCreateFileReferenceURL(nil, url as CFURL, nil).map {
            CFURLGetString($0.takeRetainedValue()) as String
        }
    }

    public func resolvedURL() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale), matches(url) { return url }
        }
        if let referenceURLString, referenceURLString.hasPrefix("file:///.file/id="),
           let reference = CFURLCreateWithString(nil, referenceURLString as CFString, nil),
           let path = CFURLCreateFilePathURL(nil, reference, nil)?.takeRetainedValue() {
            let url = path as URL
            if matches(url) { return url }
        }
        return matches(originalURL) ? originalURL : nil
    }

    private func matches(_ url: URL) -> Bool {
        guard url.isFileURL, let identity = try? FileIdentity.read(url) else { return false }
        return identity.device == device && identity.inode == inode
    }
}

public enum ShelfContent: Codable, Equatable, Sendable {
    case file(ShelfFileReference), text(String), link(URL)

    public var localizedTitle: String {
        switch self {
        case .file: String(localized: "Dosya")
        case .text: String(localized: "Metin")
        case .link: String(localized: "Web bağlantısı")
        }
    }

    public var title: String {
        switch self {
        case .file(let file): return file.resolvedURL()?.lastPathComponent ?? file.originalURL.lastPathComponent
        case .text(let text):
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return line.count > 120 ? String(line.prefix(120)) + "…" : line
        case .link(let url): return url.absoluteString
        }
    }

    public var plainText: String {
        switch self {
        case .file(let file): (file.resolvedURL() ?? file.originalURL).path
        case .text(let text): text
        case .link(let url): url.absoluteString
        }
    }

    public static func fromText(_ text: String) -> Self {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false {
            return .link(url)
        }
        return .text(text)
    }

    var isValid: Bool {
        switch self {
        case .file(let file): file.originalURL.isFileURL && file.originalURL.path.utf8.count <= 16_384
        case .text(let text): !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= ShelfCollection.maximumTextBytes
        case .link(let url): ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false && url.absoluteString.utf8.count <= ShelfCollection.maximumTextBytes
        }
    }

    func isDuplicate(of other: Self) -> Bool {
        switch (self, other) {
        case (.file(let a), .file(let b)): a.device == b.device && a.inode == b.inode
        default: self == other
        }
    }
}

public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let content: ShelfContent
    public var pinned: Bool
    public let addedAt: Date

    public init(id: UUID = UUID(), content: ShelfContent, pinned: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.pinned = pinned
        self.addedAt = addedAt
    }
}

/// A bounded collection never evicts an existing item to make room for a new drop.
public struct ShelfCollection: Equatable, Sendable {
    public static let capacity = 100
    public static let maximumTextBytes = 262_144
    public private(set) var items: [ShelfItem] = []
    public var remainingCapacity: Int { Self.capacity - items.count }

    public struct Insertion: Sendable {
        public var added: [ShelfItem] = []
        public var duplicates = 0
        public var rejected = 0
        public init() {}
    }

    public init(items: [ShelfItem] = []) {
        var ids: Set<UUID> = []
        for item in items where self.items.count < Self.capacity && item.content.isValid {
            guard ids.insert(item.id).inserted, !self.items.contains(where: { $0.content.isDuplicate(of: item.content) }) else { continue }
            self.items.append(item)
        }
    }

    @discardableResult
    public mutating func insert(_ contents: [ShelfContent], reserving reserved: Int = 0) -> Insertion {
        var result = Insertion()
        let limit = max(0, Self.capacity - max(0, reserved))
        for content in contents {
            guard content.isValid else { result.rejected += 1; continue }
            guard !items.contains(where: { $0.content.isDuplicate(of: content) }) else { result.duplicates += 1; continue }
            guard items.count < limit else { result.rejected += 1; continue }
            let item = ShelfItem(content: content)
            items.append(item)
            result.added.append(item)
        }
        return result
    }

    public mutating func togglePins(_ ids: Set<UUID>) {
        let pin = items.contains { ids.contains($0.id) && !$0.pinned }
        for index in items.indices where ids.contains(items[index].id) { items[index].pinned = pin }
    }

    @discardableResult
    public mutating func remove(_ ids: Set<UUID>) -> [ShelfItem] {
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        return removed
    }

    @discardableResult
    public mutating func clearUnpinned() -> [ShelfItem] { remove(Set(items.filter { !$0.pinned }.map(\.id))) }
}

public struct ShelfArchive: Codable, Sendable {
    public let version: Int
    public let items: [ShelfItem]
    public init(items: [ShelfItem]) { version = 1; self.items = items }

    public static func decode(_ data: Data) throws -> ShelfCollection {
        guard data.count <= 32 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return ShelfCollection(items: archive.items)
    }
}
