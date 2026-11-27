import SSHConfigKit

enum Banner: Hashable, Identifiable, Sendable {
    case missingFile
    case notDownloaded
    case notUTF8
    case unreadable(String)
    case byteOrderMark
    case unparsableLines(first: Int, count: Int)
    case externalChange
    case notWatching

    var id: Self { self }
}

@MainActor
enum BannerBuilder {
    /// Most important first: load problems, then BOM, then external changes, then watcher status.
    static func banners(for store: ConfigStore) -> [Banner] {
        var banners: [Banner] = []
        switch store.loadState {
        case .missing: banners.append(.missingFile)
        case .notDownloaded: banners.append(.notDownloaded)
        case .notUTF8: banners.append(.notUTF8)
        case .unreadable(let detail): banners.append(.unreadable(detail))
        case .loaded:
            if store.document.hasByteOrderMark { banners.append(.byteOrderMark) }
            let bad = store.document.unparsableLineNumbers
            if let first = bad.first { banners.append(.unparsableLines(first: first, count: bad.count)) }
        }
        if store.externalChangePending { banners.append(.externalChange) }
        if !store.isWatching { banners.append(.notWatching) }
        return banners
    }
}
