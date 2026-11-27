import Foundation

// MARK: - Catalog

public enum CleanupSafety: String, Codable, Sendable {
    /// Rebuilt automatically by the owning app; selected by default.
    case safe
    /// Might hold something the user wants; listed but never preselected.
    case review

    public var title: String { self == .safe ? String(localized: "Güvenli") : String(localized: "İncele") }
}

public enum CleanupGroup: String, Sendable, CaseIterable, Identifiable {
    case system, developer, packages, apps, downloads, separate, trash
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: String(localized: "Sistem Çöpü")
        case .developer: String(localized: "Xcode ve Geliştirici")
        case .packages: String(localized: "Paket Yöneticileri")
        case .apps: String(localized: "Uygulama Önbellekleri")
        case .downloads: String(localized: "İndirilenler")
        case .separate: String(localized: "Ayrı Yönet")
        case .trash: String(localized: "Çöp Kutusu")
        }
    }
}

public enum CleanupTargetID: String, Sendable, CaseIterable, Codable {
    case userCaches, userLogs, derivedData, xcodeArchives, deviceSupport, simulatorCaches
    case homebrew, npm, pip, yarn, cocoapods, gradle, mailDownloads, oldDownloads, trash
    case communicationCaches, designCaches, editorCaches, installers
    /// Large data the user decides about elsewhere: listed, excluded from the cleanup total, never removable
    /// here.
    case phoneBackups, virtualMachines, localICloud
}

public struct CleanupTarget: Sendable, Identifiable {
    public enum Selection: Sendable, Equatable {
        /// Every direct child of each root is an item.
        case children
        /// Only these direct children of each root are items.
        case named([String])
        /// Only direct children with one of these extensions (case-insensitive) are items.
        case extensions([String])
    }

    public var id: CleanupTargetID
    public let title: String
    public let detail: String
    public let symbol: String
    public let group: CleanupGroup
    public let roots: [URL]
    public let selection: Selection
    public let safety: CleanupSafety
    public let preselected: Bool
    /// Children skipped because another target owns them or they are bookkeeping files.
    public let excludedNames: Set<String>
    /// Items newer than this many days are not listed (Downloads).
    public let minimumAgeDays: Int?
    /// Apps whose running state makes every item of the target unsafe to clean now.
    public let relatedBundleIDs: [String]
    public var isTrash: Bool { id == .trash }
    public var isManagedSeparately: Bool { group == .separate }
}

public enum CleanupCatalog {
    /// Bookkeeping files never offered for removal.
    static let ignoredNames: Set<String> = [".DS_Store", ".localized", ".com.apple.timemachine.supported"]

    /// Chromium/Electron cache folders: rebuilt by the app, unlike its Local Storage or databases.
    static let electronCacheNames = ["Cache", "Code Cache", "GPUCache", "DawnCache"]

    /// Cache folders under ~/Library/Caches that belong to macOS components even without a com.apple prefix.
    static let systemCacheNames: Set<String> = [
        "CloudKit", "GeoServices", "FamilyCircle", "PassKit", "Metal", "SiriTTS", "TemporaryItems",
        "familycircled", "storeassetd", "storedownloadd", "nsurlsessiond", "akd", "ColorSync", "Microsoft Edge Updater",
    ]

    public static func targets(home: URL, downloadsAgeDays: Int = 90) -> [CleanupTarget] {
        let home = URL(fileURLWithPath: existingCanonicalPath(home) ?? home.standardizedFileURL.path, isDirectory: true)
        func h(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: true) }
        let xcode = ["com.apple.dt.Xcode"]
        return [
            CleanupTarget(id: .userCaches, title: String(localized: "Kullanıcı Önbellekleri"),
                          detail: String(localized: "Uygulamaların gerektiğinde yeniden oluşturduğu önbellek klasörleri."),
                          symbol: "shippingbox.fill", group: .system, roots: [h("Library/Caches")], selection: .children,
                          safety: .safe, preselected: true,
                          excludedNames: ignoredNames.union(["Homebrew", "pip", "Yarn", "CocoaPods"]),
                          minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .userLogs, title: String(localized: "Kullanıcı Günlükleri"),
                          detail: String(localized: "Uygulama günlükleri ve çökme raporları. Sorun gidermiyorsan gerekmez."),
                          symbol: "list.bullet.rectangle.fill", group: .system, roots: [h("Library/Logs")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .mailDownloads, title: String(localized: "Mail Ekleri"),
                          detail: String(localized: "Mail’in açtığın ekler için tuttuğu kopyalar. Asılları Mail’de kalır."),
                          symbol: "paperclip", group: .system,
                          roots: [h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil,
                          relatedBundleIDs: ["com.apple.mail"]),
            CleanupTarget(id: .derivedData, title: "Xcode DerivedData",
                          detail: String(localized: "Derleme ara ürünleri ve dizinler. Xcode bir sonraki derlemede yeniden oluşturur."),
                          symbol: "hammer.fill", group: .developer, roots: [h("Library/Developer/Xcode/DerivedData")],
                          selection: .children, safety: .safe, preselected: true, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: xcode),
            CleanupTarget(id: .deviceSupport, title: String(localized: "Cihaz Destek Dosyaları"),
                          detail: String(localized: "Bağladığın cihazlar için indirilen sembol dosyaları. Cihazı yeniden bağlayınca indirilir."),
                          symbol: "iphone", group: .developer,
                          roots: ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport",
                                  "macOS DeviceSupport"].map { h("Library/Developer/Xcode/" + $0) },
                          selection: .children, safety: .safe, preselected: true, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: xcode),
            CleanupTarget(id: .simulatorCaches, title: String(localized: "Simülatör Önbellekleri"),
                          detail: String(localized: "CoreSimulator’ın dyld ve görüntü önbellekleri. Simülatörler yeniden oluşturur."),
                          symbol: "ipad.and.iphone", group: .developer, roots: [h("Library/Developer/CoreSimulator/Caches")],
                          selection: .children, safety: .safe, preselected: true, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: xcode + ["com.apple.iphonesimulator"]),
            CleanupTarget(id: .xcodeArchives, title: String(localized: "Xcode Arşivleri"),
                          detail: String(localized: "Yayımladığın sürümlerin arşivleri ve dSYM’leri. Çökme raporlarını çözmek için gerekebilir."),
                          symbol: "archivebox.fill", group: .developer, roots: [h("Library/Developer/Xcode/Archives")],
                          selection: .children, safety: .review, preselected: false, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: xcode),
            CleanupTarget(id: .homebrew, title: String(localized: "Homebrew İndirmeleri"),
                          detail: String(localized: "Kurulumdan sonra tutulan paket arşivleri. brew gerektiğinde yeniden indirir."),
                          symbol: "mug.fill", group: .packages, roots: [h("Library/Caches/Homebrew")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .npm, title: String(localized: "npm Önbelleği"), detail: String(localized: "npm’in indirdiği paket önbelleği (_cacache)."),
                          symbol: "shippingbox", group: .packages, roots: [h(".npm")], selection: .named(["_cacache"]),
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .pip, title: String(localized: "pip Önbelleği"), detail: String(localized: "Python paketlerinin indirme ve wheel önbelleği."),
                          symbol: "shippingbox", group: .packages, roots: [h("Library/Caches/pip")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .yarn, title: String(localized: "Yarn Önbelleği"), detail: String(localized: "Yarn’ın paket önbelleği."),
                          symbol: "shippingbox", group: .packages, roots: [h("Library/Caches/Yarn")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .cocoapods, title: String(localized: "CocoaPods Önbelleği"), detail: String(localized: "Pod kaynaklarının yerel önbelleği."),
                          symbol: "shippingbox", group: .packages, roots: [h("Library/Caches/CocoaPods")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .gradle, title: String(localized: "Gradle Önbelleği"), detail: String(localized: "Gradle bağımlılık ve derleme önbellekleri."),
                          symbol: "shippingbox", group: .packages, roots: [h(".gradle/caches")], selection: .children,
                          safety: .safe, preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil,
                          relatedBundleIDs: ["com.google.android.studio"]),
            CleanupTarget(id: .communicationCaches, title: String(localized: "Mesajlaşma Uygulaması Önbellekleri"),
                          detail: String(localized: "Slack, Discord, Teams ve Signal’in yalnız önbellek klasörleri. Mesajlar ve ayarlar dokunulmaz."),
                          symbol: "bubble.left.and.bubble.right.fill", group: .apps,
                          roots: ["Slack", "discord", "Microsoft/Teams", "Signal"].map { h("Library/Application Support/" + $0) },
                          selection: .named(electronCacheNames), safety: .safe, preselected: true, excludedNames: ignoredNames,
                          minimumAgeDays: nil,
                          relatedBundleIDs: ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.teams", "com.microsoft.teams2",
                                             "org.whispersystems.signal-desktop"]),
            CleanupTarget(id: .designCaches, title: String(localized: "Tasarım Uygulaması Önbellekleri"),
                          detail: String(localized: "Adobe uygulamalarının ortam önbelleği. Uygulama gerektiğinde yeniden oluşturur."),
                          symbol: "paintpalette.fill", group: .apps, roots: [h("Library/Application Support/Adobe/Common")],
                          selection: .named(["Media Cache Files", "Media Cache"]), safety: .safe, preselected: true,
                          excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .editorCaches, title: String(localized: "Kod Düzenleyici Önbellekleri"),
                          detail: String(localized: "VS Code ve Cursor’ın önbellek klasörleri. Eklentiler ve ayarlar dokunulmaz."),
                          symbol: "chevron.left.forwardslash.chevron.right", group: .developer,
                          roots: ["Code", "Cursor"].map { h("Library/Application Support/" + $0) },
                          selection: .named(electronCacheNames + ["CachedData", "CachedExtensionVSIXs"]), safety: .safe,
                          preselected: true, excludedNames: ignoredNames, minimumAgeDays: nil,
                          relatedBundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"]),
            CleanupTarget(id: .oldDownloads, title: String(localized: "Eski İndirilenler"),
                          detail: String(localized: "\(downloadsAgeDays) günden uzun süredir dokunulmamış indirilen öğeler. Seçmeden önce incele."),
                          symbol: "arrow.down.circle.fill", group: .downloads, roots: [h("Downloads")], selection: .children,
                          safety: .review, preselected: false, excludedNames: ignoredNames, minimumAgeDays: downloadsAgeDays,
                          relatedBundleIDs: []),
            CleanupTarget(id: .installers, title: String(localized: "Yükleyiciler"),
                          detail: String(localized: "İndirilenler’deki DMG, PKG ve ISO dosyaları; kurulduktan sonra gerekmez. Seçmeden önce incele."),
                          symbol: "shippingbox.and.arrow.backward.fill", group: .downloads, roots: [h("Downloads")],
                          selection: .extensions(["dmg", "pkg", "iso", "xip"]), safety: .review, preselected: false,
                          excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .phoneBackups, title: String(localized: "iPhone ve iPad Yedekleri"),
                          detail: String(localized: "Bu Mac’e alınmış cihaz yedekleri. Silmek yedeği geri getirilemez yapar; Finder’dan yönet."),
                          symbol: "iphone.gen3", group: .separate, roots: [h("Library/Application Support/MobileSync/Backup")],
                          selection: .children, safety: .review, preselected: false, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .virtualMachines, title: String(localized: "Sanal Makineler"),
                          detail: String(localized: "Parallels, UTM ve VMware sanal makineleri. Uygulamasından yönet; burada silinmez."),
                          symbol: "macwindow.on.rectangle", group: .separate,
                          roots: [h("Parallels"), h("Virtual Machines.localized"), h("Library/Containers/com.utmapp.UTM/Data/Documents")],
                          selection: .children, safety: .review, preselected: false, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .localICloud, title: String(localized: "Bu Mac’teki iCloud Dosyaları"),
                          detail: String(localized: "iCloud’dan indirilmiş uygulama ve belge verileri. Silmek iCloud’dan da silebilir; Finder’dan yönet."),
                          symbol: "icloud.fill", group: .separate, roots: [h("Library/Mobile Documents")],
                          selection: .children, safety: .review, preselected: false, excludedNames: ignoredNames,
                          minimumAgeDays: nil, relatedBundleIDs: []),
            CleanupTarget(id: .trash, title: String(localized: "Çöp Kutusu"),
                          detail: String(localized: "Çöp’teki öğeler boşaltılana kadar yer kaplar. Boşaltma geri alınamaz."),
                          symbol: "trash.fill", group: .trash, roots: [h(".Trash")], selection: .children,
                          safety: .review, preselected: false, excludedNames: ignoredNames, minimumAgeDays: nil, relatedBundleIDs: []),
        ]
    }
}

// MARK: - Safety rules

public struct RunningApplicationInfo: Sendable, Equatable {
    public let bundleID: String?
    public let name: String?
    public init(bundleID: String?, name: String?) { self.bundleID = bundleID; self.name = name }
}

public enum CleanupRules {
    public static var runningWarning: String { String(localized: "Uygulama açıkken önbelleği yeniden oluşabilir; önce uygulamayı kapat.") }
    public static var systemWarning: String { String(localized: "macOS bileşenine ait. Yalnız ne olduğunu biliyorsan seç.") }

    /// The running app that owns a cache folder named `name`, if any. Matches the bundle identifier
    /// (exactly or as a prefix such as `com.example.app.helper`) or the app's name, case-insensitively.
    public static func runningOwner(of name: String, running: [RunningApplicationInfo]) -> RunningApplicationInfo? {
        let lowered = name.lowercased()
        return running.first { app in
            if let id = app.bundleID?.lowercased(), !id.isEmpty, lowered == id || lowered.hasPrefix(id + ".") { return true }
            if let appName = app.name?.lowercased(), !appName.isEmpty, lowered == appName { return true }
            return false
        }
    }

    public static func isSystemCache(_ name: String) -> Bool {
        name.hasPrefix("com.apple.") || CleanupCatalog.systemCacheNames.contains(name)
    }

    public struct Assessment: Sendable, Equatable {
        public let safety: CleanupSafety
        public let preselected: Bool
        public let warning: String?
    }

    public static func assess(target: CleanupTarget, name: String, running: [RunningApplicationInfo]) -> Assessment {
        var safety = target.safety
        var preselected = target.preselected
        var warning: String?
        if target.id == .userCaches || target.id == .userLogs, isSystemCache(name) {
            safety = .review
            preselected = false
            warning = systemWarning
        }
        let runningIDs = Set(running.compactMap { $0.bundleID?.lowercased() })
        if let related = target.relatedBundleIDs.first(where: { runningIDs.contains($0.lowercased()) }) {
            let owner = running.first { $0.bundleID?.lowercased() == related.lowercased() }?.name ?? related
            preselected = false
            warning = String(localized: "\(owner) açık. Temizlemeden önce kapatman önerilir.")
        } else if target.id == .userCaches, runningOwner(of: name, running: running) != nil {
            preselected = false
            warning = runningWarning
        }
        return Assessment(safety: safety, preselected: preselected && safety == .safe, warning: warning)
    }
}

// MARK: - Scan results

public struct CleanupItem: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let targetID: CleanupTargetID
    public let url: URL
    /// Canonical root the item is a direct child of.
    public let root: URL
    public let identity: FileIdentity
    public let measurement: StorageMeasurement
    public let safety: CleanupSafety
    public let preselected: Bool
    public let warning: String?
    public let isPackage: Bool
    /// Most recent of the item's own date, its date added and its newest file.
    public let lastUsed: Date
    /// Shown instead of the file name when the name alone is ambiguous ("Slack › Cache").
    public var label: String? = nil
    public var name: String { url.lastPathComponent }
    public var bytes: Int64 { measurement.allocatedBytes }
}

public struct CleanupTargetReport: Identifiable, Sendable {
    public enum State: Sendable, Equatable {
        case ready
        /// No root exists on this Mac.
        case missing
        /// A root exists but cannot be listed (usually Full Disk Access).
        case inaccessible(String)
        /// A root is a symbolic link; it is reported and never followed.
        case symbolicLink
    }

    public var id: CleanupTargetID { target.id }
    public let target: CleanupTarget
    public var items: [CleanupItem]
    public let state: State
    public let complete: Bool
    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var fileCount: Int { items.reduce(0) { $0 + $1.measurement.fileCount } }
}

public struct CleanupReport: Sendable {
    public let scannedAt: Date
    public let duration: TimeInterval
    public var targets: [CleanupTargetReport]
    public let limitReached: Bool
    /// Totals cover what this app can clean; separately managed data is listed but not counted.
    public var bytes: Int64 { cleanable.reduce(0) { $0 + $1.bytes } }
    public var itemCount: Int { cleanable.reduce(0) { $0 + $1.items.count } }
    private var cleanable: [CleanupTargetReport] { targets.filter { !$0.target.isManagedSeparately } }
}

// MARK: - Scanner

public struct CleanupScanner: Sendable {
    public init() {}

    public func scan(_ targets: [CleanupTarget], running: [RunningApplicationInfo] = [], now: Date = Date(),
                     control: StorageScanControl, concurrency: Int = 4) async throws -> CleanupReport {
        let started = Date()
        let links = HardLinkRegistry()
        var reports: [CleanupTargetReport] = []
        try await withThrowingTaskGroup(of: CleanupTargetReport.self) { group in
            var pending = targets[...]
            func launch() {
                guard let target = pending.popFirst() else { return }
                group.addTask {
                    await StorageWork.run(control) { Self.scan(target, running: running, now: now, control: control, links: links) }
                }
            }
            for _ in 0..<max(1, concurrency) { launch() }
            while let report = try await group.next() {
                reports.append(report)
                launch()
            }
        }
        if control.isCancelled { throw CancellationError() }
        let order = Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($1.id, $0) })
        reports.sort { order[$0.id, default: 0] < order[$1.id, default: 0] }
        // One path can match two targets (an old installer is also an old download); the first listed target
        // owns it.
        var claimed = Set<String>()
        for index in reports.indices { reports[index].items.removeAll { !claimed.insert($0.id).inserted } }
        return CleanupReport(scannedAt: started, duration: Date().timeIntervalSince(started), targets: reports,
                             limitReached: control.limitReached)
    }

    static func scan(_ target: CleanupTarget, running: [RunningApplicationInfo], now: Date,
                     control: StorageScanControl, links: HardLinkRegistry) -> CleanupTargetReport {
        var items: [CleanupItem] = []
        var existing = 0
        var inaccessible: String?
        var symlinked = false
        var complete = true
        let cutoff = target.minimumAgeDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
        control.beginTarget(target.title)
        defer { control.endTarget(target.title) }
        for root in target.roots {
            guard let rootIdentity = lstatIdentity(root.path) else { continue }
            existing += 1
            if rootIdentity.isSymbolicLink || existingCanonicalPath(root) != root.path { symlinked = true; continue }
            guard rootIdentity.isDirectory else { continue }
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: root.path)
            } catch {
                inaccessible = (error as NSError).code == NSFileReadNoPermissionError
                    ? String(localized: "Erişim izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Tam Disk Erişimi’nden izin verebilirsin.")
                    : error.localizedDescription
                complete = false
                continue
            }
            let wanted: Set<String>? = if case .named(let list) = target.selection { Set(list) } else { nil }
            let extensions: Set<String>? = if case .extensions(let list) = target.selection { Set(list) } else { nil }
            let named: Bool = if case .named = target.selection { true } else { false }
            for name in names.sorted() {
                if control.isCancelled || control.limitReached { complete = false; break }
                if target.excludedNames.contains(name) { continue }
                if let wanted, !wanted.contains(name) { continue }
                if let extensions, !extensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) { continue }
                let url = root.appendingPathComponent(name)
                // Symlinks are never followed, measured or offered.
                guard let identity = lstatIdentity(url.path), !identity.isSymbolicLink else { continue }
                let measurement = DirectorySizer.measure(url.path, control: control, links: links)
                if !measurement.complete { complete = false }
                guard measurement.allocatedBytes > 0 || target.isTrash else { continue }
                let added = (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
                let lastUsedSeconds = max(identity.modifiedSeconds, measurement.newestModification,
                                          Int64(added?.timeIntervalSince1970 ?? 0))
                let lastUsed = Date(timeIntervalSince1970: Double(lastUsedSeconds))
                if let cutoff, lastUsed >= cutoff { continue }
                let assessment = CleanupRules.assess(target: target, name: name, running: running)
                items.append(CleanupItem(targetID: target.id, url: url, root: root, identity: identity, measurement: measurement,
                                         safety: assessment.safety, preselected: assessment.preselected && !target.isManagedSeparately,
                                         warning: assessment.warning, isPackage: identity.isDirectory && FileScanner.isPackage(url),
                                         lastUsed: lastUsed,
                                         label: named && target.roots.count > 1 ? root.lastPathComponent + " › " + name : nil))
            }
        }
        items.sort { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }
        let state: CleanupTargetReport.State
        if let inaccessible, items.isEmpty { state = .inaccessible(inaccessible) }
        else if symlinked, items.isEmpty { state = .symbolicLink }
        else if existing == 0 { state = .missing }
        else { state = .ready }
        return CleanupTargetReport(target: target, items: items, state: state, complete: complete)
    }
}

// MARK: - Removal

public enum CleanupError: Error, LocalizedError, Equatable {
    case trashItem, unknownTarget, notDirectChild, excluded, managedSeparately, protected
    public var errorDescription: String? {
        switch self {
        case .trashItem: String(localized: "Çöp’teki öğeler yalnız Çöp boşaltılarak silinir.")
        case .unknownTarget: String(localized: "Öğe bilinen bir temizlik konumuna ait değil.")
        case .notDirectChild: String(localized: "Yalnız temizlik konumunun doğrudan içindeki öğeler taşınabilir.")
        case .excluded: String(localized: "Bu öğe temizlik kapsamı dışında tutuluyor.")
        case .managedSeparately: String(localized: "Bu veri Ayrı Yönet grubunda; burada silinmez.")
        case .protected: String(localized: "Bu öğeyi korumaya aldın; temizlenmez.")
        }
    }
}

public enum CleanupRemovalPolicy {
    /// Checks that an item still is exactly what was scanned, sits directly inside one of its target's
    /// roots, has no symlink anywhere in its path and passes the general Trash validation.
    public static func validate(_ item: CleanupItem, targets: [CleanupTarget], protectedPaths: Set<String> = []) throws {
        guard let target = targets.first(where: { $0.id == item.targetID }) else { throw CleanupError.unknownTarget }
        if target.isTrash { throw CleanupError.trashItem }
        if target.isManagedSeparately { throw CleanupError.managedSeparately }
        if protectedPaths.contains(item.url.path) { throw CleanupError.protected }
        guard target.roots.contains(where: { $0.path == item.root.path }) else { throw CleanupError.unknownTarget }
        guard let rootIdentity = lstatIdentity(item.root.path), rootIdentity.isDirectory,
              existingCanonicalPath(item.root) == item.root.path else { throw FileServiceError.symbolicLink }
        guard item.url.deletingLastPathComponent().path == item.root.path else { throw CleanupError.notDirectChild }
        let name = item.url.lastPathComponent
        if target.excludedNames.contains(name) { throw CleanupError.excluded }
        if case .named(let names) = target.selection, !names.contains(name) { throw CleanupError.excluded }
        if case .extensions(let list) = target.selection, !list.contains(item.url.pathExtension.lowercased()) { throw CleanupError.excluded }
        guard !item.identity.isSymbolicLink, existingCanonicalPath(item.url) == item.url.path else {
            throw FileServiceError.symbolicLink
        }
        try FileTrashRequest(url: item.url, identity: item.identity, root: item.root).validate()
    }
}

/// Removes validated cleanup items, permanently or through the Trash.
public actor CleanupService {
    private let trash: FileTrashService
    public init() { trash = FileTrashService() }
    init(move: @escaping @Sendable (URL) throws -> URL, delete: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        trash = FileTrashService(move: move, delete: delete)
    }

    public func remove(_ items: [CleanupItem], targets: [CleanupTarget], mode: RemovalMode,
                       protectedPaths: Set<String> = []) async -> [FileTrashResult] {
        var results: [FileTrashResult] = []
        for item in items {
            if Task.isCancelled { break }
            do {
                try CleanupRemovalPolicy.validate(item, targets: targets, protectedPaths: protectedPaths)
            } catch {
                results.append(.init(source: item.url, trashURL: nil, error: error.localizedDescription, mode: mode))
                continue
            }
            // FileTrashService revalidates immediately before removing.
            results += await trash.remove([FileTrashRequest(url: item.url, identity: item.identity, root: item.root)], mode: mode)
        }
        return results
    }

    public func moveToTrash(_ items: [CleanupItem], targets: [CleanupTarget], protectedPaths: Set<String> = []) async -> [FileTrashResult] {
        await remove(items, targets: targets, mode: .moveToTrash, protectedPaths: protectedPaths)
    }
}

// MARK: - Emptying the Trash

/// Permanently deletes items that sit directly inside the user's `~/.Trash`.
///
/// Chosen over asking Finder to `empty trash` via AppleScript: that needs an Automation permission,
/// empties the Trash of every volume and deletes items this app never showed or validated. Here only
/// the exact items listed to the user are removed, each revalidated (same inode, same parent, no
/// symlinked path) right before removal; symlinks are unlinked, never followed.
public struct TrashEmptier: Sendable {
    public let home: URL
    public let trashRoot: URL
    private let remove: @Sendable (URL) throws -> Void

    public init(home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        self.init(home: home) { try FileManager.default.removeItem(at: $0) }
    }

    init(home: URL, remove: @escaping @Sendable (URL) throws -> Void) {
        let canonicalHome = URL(fileURLWithPath: existingCanonicalPath(home) ?? home.standardizedFileURL.path, isDirectory: true)
        self.home = canonicalHome
        trashRoot = canonicalHome.appendingPathComponent(".Trash", isDirectory: true)
        self.remove = remove
    }

    public func validate(_ url: URL, identity: FileIdentity) throws {
        guard let rootIdentity = lstatIdentity(trashRoot.path), rootIdentity.isDirectory, !rootIdentity.isSymbolicLink,
              existingCanonicalPath(trashRoot) == trashRoot.path else { throw FileServiceError.symbolicLink }
        let parent = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        guard parent.path == trashRoot.path, !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw FileServiceError.outsideScope
        }
        // The parent must resolve to the Trash itself; the item may be a symlink (it is unlinked, not
        // followed).
        guard existingCanonicalPath(parent) == trashRoot.path else { throw FileServiceError.symbolicLink }
        guard let current = lstatIdentity(url.path), current == identity else { throw FileServiceError.changed }
        if !identity.isSymbolicLink, existingCanonicalPath(url) != url.path { throw FileServiceError.symbolicLink }
    }

    public struct Result: Sendable {
        public let removed: [URL]
        public let failures: [(url: URL, message: String)]
        public let removedBytes: Int64
    }

    public func empty(_ items: [CleanupItem]) async -> Result {
        var removed: [URL] = []
        var failures: [(URL, String)] = []
        var bytes: Int64 = 0
        for item in items {
            if Task.isCancelled { break }
            do {
                guard item.targetID == .trash else { throw CleanupError.unknownTarget }
                try validate(item.url, identity: item.identity)
                try remove(item.url)
                removed.append(item.url)
                bytes += item.bytes
            } catch {
                failures.append((item.url, error.localizedDescription))
            }
            await Task.yield()
        }
        return Result(removed: removed, failures: failures, removedBytes: bytes)
    }
}

// MARK: - Protected items

/// Items the user marked "keep": never selected, never moved, remembered across scans and launches.
public struct CleanupProtection: Equatable, Sendable {
    public static let storageKey = "MacPocket.cleanup.protected"
    public private(set) var paths: Set<String> = []

    public init() {}

    public func contains(_ path: String) -> Bool { paths.contains(path) }

    public mutating func toggle(_ path: String) {
        if !paths.insert(path).inserted { paths.remove(path) }
    }

    public static func load(from defaults: UserDefaults) -> CleanupProtection {
        var protection = CleanupProtection()
        protection.paths = Set(defaults.stringArray(forKey: storageKey) ?? [])
        return protection
    }

    public func save(to defaults: UserDefaults) { defaults.set(paths.sorted(), forKey: Self.storageKey) }
}
