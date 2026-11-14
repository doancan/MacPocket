import Foundation

/// What the optional Disk Röntgeni menu bar item shows next to its icon.
public enum SystemDataMenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case off, icon, systemData, freeSpace
    public var id: String { rawValue }

    public static let key = "MacPocket.systemData.menuBar"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .off
    }

    public var showsItem: Bool { self != .off }

    /// The text beside the icon, nil when only the icon is shown or nothing is known yet.
    public func title(for summary: SystemDataSummary?) -> String? {
        guard let summary else { return nil }
        func size(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file, spellsOutZero: false)) }
        switch self {
        case .off, .icon: return nil
        case .systemData: return size(summary.systemDataBytes)
        case .freeSpace: return summary.freeBytes > 0 ? size(summary.freeBytes) : nil
        }
    }
}
