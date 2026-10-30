import Foundation

/// One-click system actions.
public enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case lockScreen, sleepDisplay, sleepMac, toggleDarkMode, toggleDesktopIcons, ejectDisks, emptyTrash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lockScreen: String(localized: "Ekranı kilitle")
        case .sleepDisplay: String(localized: "Ekranı uyut")
        case .sleepMac: String(localized: "Mac’i uyut")
        case .toggleDarkMode: String(localized: "Karanlık / açık görünüm")
        case .toggleDesktopIcons: String(localized: "Masaüstü simgelerini gizle / göster")
        case .ejectDisks: String(localized: "Diskleri çıkar")
        case .emptyTrash: String(localized: "Çöp’ü boşalt")
        }
    }

    public var detail: String {
        switch self {
        case .lockScreen: String(localized: "Oturum açık kalır; dönmek için parola gerekir.")
        case .sleepDisplay: String(localized: "Ekranlar kapanır; işler çalışmaya devam eder.")
        case .sleepMac: String(localized: "Mac uyku moduna geçer.")
        case .toggleDarkMode: String(localized: "Sistem görünümünü karanlık ile açık arasında değiştirir.")
        case .toggleDesktopIcons: String(localized: "Ekran paylaşırken veya kayıt alırken masaüstünü temiz gösterir; Finder yeniden başlar.")
        case .ejectDisks: String(localized: "Takılı harici diskleri ve disk görüntülerini güvenle çıkarır.")
        case .emptyTrash: String(localized: "Finder ile tüm Çöp kutularını kalıcı olarak boşaltır.")
        }
    }

    public var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "display"
        case .sleepMac: "moon.fill"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .toggleDesktopIcons: "menubar.dock.rectangle"
        case .ejectDisks: "eject.fill"
        case .emptyTrash: "trash.fill"
        }
    }

    /// Irreversible or disruptive actions ask first.
    public var needsConfirmation: Bool { self == .emptyTrash || self == .sleepMac }
}

/// A mounted volume, reduced to what decides whether it may be ejected.
public struct MountedVolume: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let isEjectable: Bool
    public let isRemovable: Bool
    public let isInternal: Bool
    public let isRoot: Bool

    public init(url: URL, name: String, isEjectable: Bool, isRemovable: Bool, isInternal: Bool, isRoot: Bool) {
        self.url = url; self.name = name; self.isEjectable = isEjectable; self.isRemovable = isRemovable
        self.isInternal = isInternal; self.isRoot = isRoot
    }

    /// External disks, card readers and mounted disk images; never the startup disk, its system volumes or
    /// internal partitions.
    public var canEject: Bool {
        guard !isRoot, !url.path.hasPrefix("/System/Volumes") else { return false }
        return isEjectable || isRemovable || !isInternal
    }
}
