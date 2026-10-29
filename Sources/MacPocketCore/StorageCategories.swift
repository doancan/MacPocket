import Foundation

/// Categories of the volume overview, in display order. "Sistem ve Diğer" is derived
/// (used space minus everything measured) and is not walked.
public enum StorageCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case applications, documents, developer, appData, caches, logs, downloads, photos, media, otherUser, trash, system
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .applications: String(localized: "Uygulamalar")
        case .documents: String(localized: "Belgeler")
        case .developer: String(localized: "Geliştirici")
        case .appData: String(localized: "Uygulama Verileri")
        case .caches: String(localized: "Önbellekler")
        case .logs: String(localized: "Günlükler")
        case .downloads: String(localized: "İndirilenler")
        case .photos: String(localized: "Fotoğraflar")
        case .media: String(localized: "Müzik ve Filmler")
        case .otherUser: String(localized: "Diğer Kullanıcı Dosyaları")
        case .trash: String(localized: "Çöp Kutusu")
        case .system: String(localized: "Sistem ve Diğer")
        }
    }

    public var detail: String {
        switch self {
        case .applications: String(localized: "/Applications ve ~/Applications içindeki uygulama paketleri.")
        case .documents: String(localized: "Belgeler, Masaüstü ve yerelde tutulan iCloud Drive dosyaları.")
        case .developer: String(localized: "Xcode verileri, simülatörler ve paket yöneticisi önbellekleri.")
        case .appData: String(localized: "Uygulamaların ~/Library/Application Support altında tuttuğu veriler.")
        case .caches: String(localized: "Uygulamaların yeniden oluşturabildiği önbellek dosyaları.")
        case .logs: String(localized: "Uygulama ve sistem günlükleri, çökme raporları.")
        case .downloads: String(localized: "İndirilenler klasörü.")
        case .photos: String(localized: "Resimler klasörü ve Fotoğraflar arşivi (tek paket olarak).")
        case .media: String(localized: "Müzik ve Filmler klasörleri, Müzik ve TV arşivleri.")
        case .otherUser: String(localized: "Ev klasöründeki diğer klasörler: projeler, gizli klasörler ve araç verileri (~/Library hariç).")
        case .trash: String(localized: "Çöp Kutusu’ndaki öğeler; Çöp boşaltılana kadar yer kaplar.")
        case .system: String(localized: "macOS, sanal bellek, APFS anlık görüntüleri ve ölçülmeyen diğer veriler.")
        }
    }

    public var symbol: String {
        switch self {
        case .applications: "app.badge"
        case .documents: "doc.text"
        case .developer: "hammer"
        case .appData: "archivebox"
        case .caches: "shippingbox"
        case .logs: "list.bullet.rectangle"
        case .downloads: "arrow.down.circle"
        case .photos: "photo.on.rectangle"
        case .media: "music.note"
        case .otherUser: "person.crop.square"
        case .trash: "trash"
        case .system: "gearshape.2"
        }
    }

    /// Roots measured for the category. Paths that are another category's root are pruned from walks,
    /// so nested roots (e.g. Xcode caches under ~/Library/Caches) are never counted twice.
    public func roots(home: URL) -> [URL] {
        func h(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: true) }
        switch self {
        case .applications: return [URL(fileURLWithPath: "/Applications", isDirectory: true), h("Applications")]
        case .documents: return [h("Documents"), h("Desktop"), h("Library/Mobile Documents")]
        case .developer:
            return [h("Library/Developer"), h(".npm"), h(".gradle"), h(".cargo"), h(".rustup"), h(".m2"), h(".pub-cache"),
                    h(".cocoapods"), h(".android"), h("Library/Caches/Homebrew"), h("Library/Caches/pip"),
                    h("Library/Caches/Yarn"), h("Library/Caches/CocoaPods"), h("Library/Caches/com.apple.dt.Xcode")]
        case .appData: return [h("Library/Application Support")]
        case .caches: return [h("Library/Caches")]
        case .logs: return [h("Library/Logs")]
        case .downloads: return [h("Downloads")]
        case .photos: return [h("Pictures")]
        case .media: return [h("Music"), h("Movies")]
        case .otherUser: return [home]
        case .trash: return [h(".Trash")]
        case .system: return []
        }
    }

    /// Paths never walked for this category besides other categories' roots. The rest of ~/Library
    /// (other apps' containers, Mail, Messages…) is left to "Sistem ve Diğer": reading it triggers
    /// privacy prompts and it is not user-managed data.
    public func excludedPaths(home: URL) -> Set<String> {
        self == .otherUser ? [home.appendingPathComponent("Library").path] : []
    }
}

public struct StorageItemUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let allocatedBytes: Int64
    public let isPackage: Bool
}

public struct StorageCategoryUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: StorageCategory { category }
    public let category: StorageCategory
    public var measurement: StorageMeasurement
    /// Largest top-level items of the category's roots (packages counted as one item).
    public var largestItems: [StorageItemUsage]
    /// Roots that exist; missing roots are simply skipped.
    public var measuredRoots: [String]
    public var bytes: Int64 { measurement.allocatedBytes }
}

public struct StorageOverviewReport: Codable, Sendable, Equatable {
    public let scannedAt: Date
    public let duration: TimeInterval
    public let volume: VolumeCapacity
    public let categories: [StorageCategoryUsage]
    /// True when the budget ran out or the scan was cancelled.
    public let limitReached: Bool

    public var measuredBytes: Int64 { categories.reduce(0) { $0 + $1.bytes } }
    /// Used space not attributed to a measured category.
    public var systemAndOtherBytes: Int64 { max(0, volume.usedBytes - measuredBytes) }
    public var isPartial: Bool { limitReached || categories.contains { !$0.measurement.complete } }

    /// Measured categories plus the derived "Sistem ve Diğer" slice, largest first except system last.
    public var segments: [(category: StorageCategory, bytes: Int64)] {
        categories.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }.map { ($0.category, $0.bytes) }
            + [(StorageCategory.system, systemAndOtherBytes)]
    }
}

public struct StorageOverviewOptions: Sendable {
    /// Time and entry budgets live in the `StorageScanControl` passed to `scan`.
    public var home: URL
    public var largestItemCount = 8
    public var categories: [StorageCategory] = StorageCategory.allCases.filter { $0 != .system }
    /// Parallel category walks; the SSD and the metadata cache handle a few at once well.
    public var concurrency = 4
    /// Overridable for tests; nil reads the volume that holds `home`.
    public var volume: VolumeCapacity?
    public init(home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) { self.home = home }
}

/// Measures the storage categories of a volume with allocated sizes.
public struct StorageOverviewScanner: Sendable {
    public init() {}

    public func scan(_ options: StorageOverviewOptions, control: StorageScanControl) async throws -> StorageOverviewReport {
        let started = Date()
        let volume = try options.volume ?? VolumeCapacity.read(options.home)
        let links = HardLinkRegistry()
        let home = URL(fileURLWithPath: existingCanonicalPath(options.home) ?? options.home.path, isDirectory: true)
        // Every category root, canonical; used to prune nested roots of other categories.
        var rootsByCategory: [StorageCategory: [String]] = [:]
        var exclusions: [StorageCategory: Set<String>] = [:]
        for category in options.categories {
            rootsByCategory[category] = category.roots(home: home).compactMap { url in
                // Missing roots and roots that are symlinks are skipped, never followed.
                guard let identity = lstatIdentity(url.path), identity.isDirectory,
                      let canonical = existingCanonicalPath(url), canonical == url.path else { return nil }
                return canonical
            }
            exclusions[category] = category.excludedPaths(home: home)
        }
        let allRoots = Set(rootsByCategory.values.flatMap { $0 })
        let largest = options.largestItemCount
        var usages: [StorageCategoryUsage] = []
        try await withThrowingTaskGroup(of: StorageCategoryUsage.self) { group in
            var pending = options.categories[...]
            func launch() {
                guard let category = pending.popFirst() else { return }
                let roots = rootsByCategory[category] ?? []
                let excluded = allRoots.union(exclusions[category] ?? [])
                group.addTask {
                    await StorageWork.run(control) {
                        Self.measure(category: category, roots: roots, allRoots: excluded, largest: largest,
                                     control: control, links: links)
                    }
                }
            }
            for _ in 0..<max(1, options.concurrency) { launch() }
            while let usage = try await group.next() {
                usages.append(usage)
                launch()
            }
        }
        if control.isCancelled { throw CancellationError() }
        let order = Dictionary(uniqueKeysWithValues: StorageCategory.allCases.enumerated().map { ($1, $0) })
        usages.sort { order[$0.category, default: 0] < order[$1.category, default: 0] }
        return StorageOverviewReport(scannedAt: started, duration: Date().timeIntervalSince(started), volume: volume,
                                     categories: usages, limitReached: control.limitReached)
    }

    /// Walks each root one top-level child at a time so the largest items can be reported.
    /// `allRoots` holds every path to prune (other categories' roots and category exclusions).
    static func measure(category: StorageCategory, roots: [String], allRoots: Set<String>, largest: Int,
                        control: StorageScanControl, links: HardLinkRegistry) -> StorageCategoryUsage {
        let merged = MeasurementMerger()
        for root in roots {
            control.setCurrent(category.title)
            let excluded = allRoots.subtracting([root])
            let children: [String]
            do {
                children = try FileManager.default.contentsOfDirectory(atPath: root)
            } catch {
                merged.fail(unreadable: true)
                continue
            }
            let paths = children.map { root + "/" + $0 }.filter { !excluded.contains($0) }
            // Top-level children are independent subtrees; walk them in parallel (a home folder can hold
            // a million files in a single project folder next to many small ones).
            DispatchQueue.concurrentPerform(iterations: paths.count) { index in
                if control.isCancelled || control.limitReached { merged.fail(); return }
                let path = paths[index]
                let measurement = DirectorySizer.measure(path, control: control, links: links, excluding: excluded)
                let item = measurement.allocatedBytes > 0
                    ? StorageItemUsage(path: path, allocatedBytes: measurement.allocatedBytes,
                                       isPackage: FileScanner.isPackage(URL(fileURLWithPath: path)))
                    : nil
                merged.add(measurement, item: item, keep: largest)
            }
        }
        let (total, items) = merged.result(largest: largest)
        return StorageCategoryUsage(category: category, measurement: total, largestItems: items, measuredRoots: roots)
    }
}

/// Thread-safe accumulator for parallel child walks of one category.
private final class MeasurementMerger: @unchecked Sendable {
    private let lock = NSLock()
    private var total = StorageMeasurement()
    private var items: [StorageItemUsage] = []

    /// Marks the category partial; `unreadable` also counts an item that could not be read.
    func fail(unreadable: Bool = false) {
        lock.withLock {
            if unreadable { total.inaccessibleCount += 1 }
            total.complete = false
        }
    }

    func add(_ measurement: StorageMeasurement, item: StorageItemUsage?, keep: Int) {
        lock.withLock {
            total.add(measurement)
            guard let item else { return }
            items.append(item)
            if items.count > max(1, keep) * 4 {
                items.sort { $0.allocatedBytes > $1.allocatedBytes }
                items.removeLast(items.count - keep)
            }
        }
    }

    func result(largest: Int) -> (StorageMeasurement, [StorageItemUsage]) {
        lock.withLock {
            (total, Array(items.sorted { $0.allocatedBytes > $1.allocatedBytes }.prefix(largest)))
        }
    }
}

/// Persists the last overview so the page opens instantly with a timestamped result.
public struct StorageOverviewCache: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static var standard: StorageOverviewCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return StorageOverviewCache(url: base.appendingPathComponent("MacPocket/storage-overview.json"))
    }

    public func load() -> StorageOverviewReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(StorageOverviewReport.self, from: data)
    }

    public func save(_ report: StorageOverviewReport) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(report).write(to: url, options: .atomic)
    }
}
