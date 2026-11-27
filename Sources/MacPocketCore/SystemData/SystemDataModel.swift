import Foundation

/// How careful the user has to be before removing an item.
public enum SystemDataSafety: String, Codable, Sendable, CaseIterable, Comparable {
    /// The owning tool rebuilds it on its own; nothing is lost but time.
    case safe
    /// Costs something to get back (a download, a login, a simulator); never preselected.
    case review
    /// MacPocket does not remove it; the item explains how to do that yourself.
    case manual

    public var localizedTitle: String {
        switch self {
        case .safe: String(localized: "Güvenli")
        case .review: String(localized: "İncele")
        case .manual: String(localized: "Elle")
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
    private var order: Int { switch self { case .safe: 0; case .review: 1; case .manual: 2 } }
}

/// What it takes to get an item back after it is removed.
public enum SystemDataRegeneration: String, Codable, Sendable {
    case rebuildsLocally, downloadsAgain, notNeededAgain, doesNotReturn

    public var localizedTitle: String {
        switch self {
        case .rebuildsLocally: String(localized: "Bu Mac’te yeniden oluşur")
        case .downloadsAgain: String(localized: "Yeniden indirilir")
        case .notNeededAgain: String(localized: "Bir daha gerekmez")
        case .doesNotReturn: String(localized: "Geri gelmez")
        }
    }

    public var needsNetwork: Bool { self == .downloadsAgain }
}

public enum SystemDataGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case snapshots, simulators, xcode, packages, toolchains, aiModels, logs, temporary
    case docker, virtualMachines, trash, backups, android, appData, projects, system, other
    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .snapshots: String(localized: "Time Machine anlık görüntüleri")
        case .simulators: String(localized: "Simülatörler")
        case .xcode: String(localized: "Xcode")
        case .packages: String(localized: "Paket yöneticileri")
        case .toolchains: String(localized: "Geliştirici araçları")
        case .aiModels: String(localized: "Yapay zekâ modelleri ve araçları")
        case .logs: String(localized: "Günlükler ve tanılama")
        case .temporary: String(localized: "Geçici dosyalar")
        case .docker: String(localized: "Docker")
        case .virtualMachines: String(localized: "Sanal makineler")
        case .trash: String(localized: "Çöp Kutusu")
        case .backups: String(localized: "iOS aygıt yedekleri")
        case .android: String(localized: "Android")
        case .appData: String(localized: "Uygulama verileri ve önbellekleri")
        case .projects: String(localized: "Proje derleme klasörleri")
        case .system: String(localized: "Sistem")
        case .other: String(localized: "Diğer büyük klasörler")
        }
    }

    public var symbol: String {
        switch self {
        case .snapshots: "clock.arrow.circlepath"
        case .simulators: "iphone.gen3"
        case .xcode: "hammer"
        case .packages: "shippingbox"
        case .toolchains: "wrench.and.screwdriver"
        case .aiModels: "brain"
        case .logs: "list.bullet.rectangle"
        case .temporary: "timer"
        case .docker: "cube.box"
        case .virtualMachines: "desktopcomputer"
        case .trash: "trash"
        case .backups: "iphone.and.arrow.forward"
        case .android: "smartphone"
        case .appData: "archivebox"
        case .projects: "folder.badge.gearshape"
        case .system: "gearshape.2"
        case .other: "questionmark.folder"
        }
    }
}

/// An external program MacPocket would run for an item, shown verbatim before it runs.
public struct SystemDataCommand: Codable, Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let asAdministrator: Bool
    /// Run as the user first; ask for an administrator password only when that fails. Keeps a password prompt
    /// away from commands that macOS lets a user run on their own data (`tmutil deletelocalsnapshots` on a
    /// user snapshot).
    public let administratorFallback: Bool

    public init(_ executable: String, _ arguments: [String] = [], asAdministrator: Bool = false, administratorFallback: Bool = false) {
        self.executable = executable
        self.arguments = arguments
        self.asAdministrator = asAdministrator
        self.administratorFallback = administratorFallback
    }

    /// The same command, run as an administrator.
    public var elevated: SystemDataCommand { SystemDataCommand(executable, arguments, asAdministrator: true) }

    /// The command line as a person would type it, quoting only what needs it.
    public var displayLine: String {
        let line = ([executable] + arguments).map(Self.quoted).joined(separator: " ")
        return asAdministrator ? String(localized: "Yönetici olarak: \(line)") : line
    }

    static func quoted(_ word: String) -> String {
        guard !word.isEmpty, word.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) == nil else { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// What removing an item means.
public enum SystemDataAction: Codable, Sendable, Equatable {
    /// The item's folder itself goes.
    case removeFolder
    /// Every direct child goes; the folder stays (a cache root macOS expects to exist).
    case removeContents
    /// Direct children not touched for this many days go.
    case removeContentsOlderThan(days: Int)
    case run(SystemDataCommand)
    /// Not removable by MacPocket; the text says what to do.
    case manual(hint: String)
}

public struct SystemDataItem: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let group: SystemDataGroup
    public let title: String
    public let detail: String
    public let safety: SystemDataSafety
    public let regeneration: SystemDataRegeneration
    /// Folders this item measures, canonical and absolute. Empty for command-only items.
    public let paths: [String]
    public let sizeBytes: Int64
    /// Newest change seen inside the item, nil when it is not a folder MacPocket walked.
    public let lastActivity: Date?
    public let action: SystemDataAction
    /// Shown next to the confirmation when removal can lose data (Docker volumes, databases).
    public let warning: String?
    /// Apps that must be quit before this item is removed.
    public let busyBundleIDs: [String]
    /// False for items macOS cannot size (local snapshots); they are listed but never counted.
    public let sizeKnown: Bool
    /// The project folder a build output belongs to, so one project's costs can be grouped.
    public let projectPath: String?

    public init(id: String, group: SystemDataGroup, title: String, detail: String, safety: SystemDataSafety,
                regeneration: SystemDataRegeneration, paths: [String], sizeBytes: Int64, lastActivity: Date? = nil,
                action: SystemDataAction, warning: String? = nil, busyBundleIDs: [String] = [],
                sizeKnown: Bool = true, projectPath: String? = nil) {
        self.id = id
        self.group = group
        self.title = title
        self.detail = detail
        self.safety = safety
        self.regeneration = regeneration
        self.paths = paths
        self.sizeBytes = max(0, sizeBytes)
        self.lastActivity = lastActivity
        self.action = action
        self.warning = warning
        self.busyBundleIDs = busyBundleIDs
        self.sizeKnown = sizeKnown
        self.projectPath = projectPath
    }

    /// A single folder that is only read and costs something to rebuild can be packed into a verified archive
    /// instead of being deleted.
    public var isArchivable: Bool {
        guard case .removeFolder = action, paths.count == 1, safety == .review, sizeKnown, busyBundleIDs.isEmpty else { return false }
        return group == .projects || group == .xcode || group == .toolchains || group == .android || group == .other
    }

    /// Folders that are only ever read can be stored compressed instead of deleted, so every path keeps
    /// working.
    public var isShrinkable: Bool {
        guard safety == .review, sizeKnown, !paths.isEmpty, busyBundleIDs.isEmpty else { return false }
        switch action {
        case .removeFolder, .removeContents: break
        default: return false
        }
        return [.projects, .xcode, .toolchains, .android, .packages, .other].contains(group)
    }

    /// The same item after its size changed (for example once it was shrunk).
    public func resized(to bytes: Int64) -> SystemDataItem {
        SystemDataItem(id: id, group: group, title: title, detail: detail, safety: safety, regeneration: regeneration, paths: paths,
                       sizeBytes: bytes, lastActivity: lastActivity, action: action, warning: warning, busyBundleIDs: busyBundleIDs,
                       sizeKnown: sizeKnown, projectPath: projectPath)
    }

    public var isRemovable: Bool {
        if case .manual = action { return false }
        return safety != .manual
    }

    /// Days since the newest change inside the item; nil when unknown.
    public func idleDays(now: Date = Date()) -> Int? {
        guard let lastActivity else { return nil }
        return max(0, Int(now.timeIntervalSince(lastActivity) / 86_400))
    }
}

public struct SystemDataReport: Codable, Sendable, Equatable {
    public let scannedAt: Date
    public let items: [SystemDataItem]
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let purgeableBytes: Int64
    /// False when a time or entry budget (or a cancel) ended the scan early.
    public let complete: Bool
    /// How many places could not be read (no permission), so their sizes are missing from the totals. A
    /// finished scan with unreadable places is still a scan; the page says what is missing.
    public let unreadablePlaces: Int

    public init(scannedAt: Date, items: [SystemDataItem], totalBytes: Int64, freeBytes: Int64, purgeableBytes: Int64,
                complete: Bool, unreadablePlaces: Int = 0) {
        self.scannedAt = scannedAt
        self.items = items
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.complete = complete
        self.unreadablePlaces = max(0, unreadablePlaces)
    }

    /// True when the numbers may be lower than reality for any reason.
    public var isPartial: Bool { !complete || unreadablePlaces > 0 }

    public var systemDataBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var safeBytes: Int64 { items.filter { $0.safety == .safe && $0.isRemovable }.reduce(0) { $0 + $1.sizeBytes } }
}
