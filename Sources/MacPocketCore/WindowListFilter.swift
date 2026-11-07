import CoreGraphics
import Foundation

public enum WindowVisibilityPolicy: String, CaseIterable, Codable, Sendable {
    case show, hide, atEnd
    public var localizedTitle: String {
        switch self {
        case .show: String(localized: "Göster")
        case .hide: String(localized: "Gizle")
        case .atEnd: String(localized: "Sona taşı")
        }
    }
}

public enum WindowApplicationScope: String, CaseIterable, Codable, Sendable {
    case all, frontmost, other, pointerApplication, pointerWindows
    public var localizedTitle: String {
        switch self {
        case .all: String(localized: "Tüm uygulamalar")
        case .frontmost: String(localized: "Yalnız öndeki uygulama")
        case .other: String(localized: "Öndeki uygulama dışındakiler")
        case .pointerApplication: String(localized: "İmleç altındaki uygulama")
        case .pointerWindows: String(localized: "İmleç altındaki pencereler")
        }
    }
}

public enum WindowSpaceScope: String, CaseIterable, Codable, Sendable {
    case all, visible, notVisible
    public var localizedTitle: String {
        switch self {
        case .all: String(localized: "Tüm masaüstleri")
        case .visible: String(localized: "Görünür masaüstleri")
        case .notVisible: String(localized: "Görünür olmayan masaüstleri")
        }
    }
}

public enum WindowGrouping: String, CaseIterable, Codable, Sendable {
    case allWindows, onePerApplication
    public var localizedTitle: String {
        switch self {
        case .allWindows: String(localized: "Tüm pencereler")
        case .onePerApplication: String(localized: "Uygulama başına bir pencere")
        }
    }
}

/// Per-shortcut filters. Legacy booleans remain readable/writable for old preferences and callers.
public struct WindowListFilter: Codable, Equatable, Hashable, Sendable {
    public var minimized: WindowVisibilityPolicy = .show
    public var hidden: WindowVisibilityPolicy = .show
    public var windowless: WindowVisibilityPolicy = .hide
    public var includeFullScreen = true
    public var applicationScope: WindowApplicationScope = .all
    public var spaceScope: WindowSpaceScope = .all
    public var currentScreenOnly = false
    public var grouping: WindowGrouping = .allWindows
    public var separateTabs = false

    public var includeMinimized: Bool {
        get { minimized != .hide }
        set { minimized = newValue ? .show : .hide }
    }
    public var includeHidden: Bool {
        get { hidden != .hide }
        set { hidden = newValue ? .show : .hide }
    }
    public var includeWindowless: Bool {
        get { windowless != .hide }
        set { windowless = newValue ? .show : .hide }
    }
    public var currentApplicationOnly: Bool {
        get { applicationScope == .frontmost }
        set { applicationScope = newValue ? .frontmost : .all }
    }
    public var currentSpaceOnly: Bool {
        get { spaceScope == .visible }
        set { spaceScope = newValue ? .visible : .all }
    }
    public init() {}

    enum CodingKeys: String, CodingKey {
        case minimized, hidden, windowless, includeFullScreen, applicationScope, spaceScope, grouping, separateTabs
        case includeMinimized, includeHidden, includeWindowless, currentApplicationOnly, currentSpaceOnly, currentScreenOnly
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func legacyPolicy(_ key: CodingKeys, default fallback: Bool) throws -> WindowVisibilityPolicy {
            try (values.decodeIfPresent(Bool.self, forKey: key) ?? fallback) ? .show : .hide
        }
        minimized = try values.decodeIfPresent(String.self, forKey: .minimized).flatMap(WindowVisibilityPolicy.init(rawValue:))
            ?? legacyPolicy(.includeMinimized, default: true)
        hidden = try values.decodeIfPresent(String.self, forKey: .hidden).flatMap(WindowVisibilityPolicy.init(rawValue:))
            ?? legacyPolicy(.includeHidden, default: true)
        windowless = try values.decodeIfPresent(String.self, forKey: .windowless).flatMap(WindowVisibilityPolicy.init(rawValue:))
            ?? legacyPolicy(.includeWindowless, default: false)
        applicationScope = try values.decodeIfPresent(String.self, forKey: .applicationScope).flatMap(WindowApplicationScope.init(rawValue:))
            ?? ((values.decodeIfPresent(Bool.self, forKey: .currentApplicationOnly) ?? false) ? .frontmost : .all)
        spaceScope = try values.decodeIfPresent(String.self, forKey: .spaceScope).flatMap(WindowSpaceScope.init(rawValue:))
            ?? ((values.decodeIfPresent(Bool.self, forKey: .currentSpaceOnly) ?? false) ? .visible : .all)
        currentScreenOnly = try values.decodeIfPresent(Bool.self, forKey: .currentScreenOnly) ?? false
        includeFullScreen = try values.decodeIfPresent(Bool.self, forKey: .includeFullScreen) ?? true
        grouping = try values.decodeIfPresent(String.self, forKey: .grouping).flatMap(WindowGrouping.init(rawValue:)) ?? .allWindows
        separateTabs = try values.decodeIfPresent(Bool.self, forKey: .separateTabs) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(minimized, forKey: .minimized); try values.encode(hidden, forKey: .hidden)
        try values.encode(windowless, forKey: .windowless); try values.encode(includeFullScreen, forKey: .includeFullScreen)
        try values.encode(applicationScope, forKey: .applicationScope); try values.encode(spaceScope, forKey: .spaceScope)
        try values.encode(grouping, forKey: .grouping); try values.encode(currentScreenOnly, forKey: .currentScreenOnly)
        try values.encode(separateTabs, forKey: .separateTabs)
        try values.encode(includeMinimized, forKey: .includeMinimized); try values.encode(includeHidden, forKey: .includeHidden)
        try values.encode(includeWindowless, forKey: .includeWindowless)
        try values.encode(currentApplicationOnly, forKey: .currentApplicationOnly); try values.encode(currentSpaceOnly, forKey: .currentSpaceOnly)
    }
}

/// Captured when opening the panel, before it can cover the pointed window.
public struct WindowFilterContext: Sendable {
    public var foregroundPID: Int32?
    public var displayID: UInt32?
    /// Global CoreGraphics coordinates (top-left origin).
    public var pointerLocation: CGPoint?
    public var pointerApplicationPID: Int32?
    public init(foregroundPID: Int32? = nil, displayID: UInt32? = nil,
                pointerLocation: CGPoint? = nil, pointerApplicationPID: Int32? = nil) {
        self.foregroundPID = foregroundPID; self.displayID = displayID
        self.pointerLocation = pointerLocation; self.pointerApplicationPID = pointerApplicationPID
    }
}

extension WindowFiltering {
    static func displayID(for frame: CGRect?, among screens: [(UInt32, CGRect)]) -> UInt32? {
        guard let frame else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let screen = screens.first(where: { $0.1.contains(center) }) { return screen.0 }
        return screens.filter { $0.1.intersection(frame).area > 0 }
            .max { $0.1.intersection(frame).area < $1.1.intersection(frame).area }?.0
    }

    /// Uses visible WindowServer stacking, not alphabetical order or an AX/windowless placeholder.
    public static func applicationUnderPointer(_ windows: [SwitchableWindow], at point: CGPoint?) -> Int32? {
        guard let point else { return nil }
        return windows.filter { isUnderPointer($0, at: point) }
            .min { ($0.zOrder ?? .max) < ($1.zOrder ?? .max) }?.processID
    }

    private static func isUnderPointer(_ window: SwitchableWindow, at point: CGPoint) -> Bool {
        window.isRealWindow && !window.minimized && !window.hidden && !window.isOnAnotherSpace
            && window.zOrder != nil && window.frame?.contains(point) == true
    }

    public static func apply(_ windows: [SwitchableWindow], filter: WindowListFilter, context: WindowFilterContext = .init(),
                             search: String = "", excludedBundlePaths: Set<String> = [], order: WindowSortOrder = .recent,
                             exceptions: [SwitcherExceptionRule] = []) -> [SwitchableWindow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let pointerPID = filter.applicationScope == .pointerApplication
            ? (context.pointerApplicationPID ?? applicationUnderPointer(windows, at: context.pointerLocation)) : nil
        let values = windows.filter { window in
            guard (filter.minimized != .hide || !window.minimized), (filter.hidden != .hide || !window.hidden),
                  (filter.windowless != .hide || window.isRealWindow), (filter.includeFullScreen || !window.fullScreen),
                  !excludedBundlePaths.contains(window.applicationURL?.path ?? ""),
                  !exceptions.contains(where: { $0.hides(window) }),
                  query.isEmpty || matches(query, "\(window.application) \(window.title)") else { return false }
            switch filter.applicationScope {
            case .all: break
            case .frontmost: guard let pid = context.foregroundPID, window.processID == pid else { return false }
            case .other: guard let pid = context.foregroundPID, window.processID != pid else { return false }
            case .pointerApplication: guard let pid = pointerPID, window.processID == pid else { return false }
            case .pointerWindows:
                guard let point = context.pointerLocation, isUnderPointer(window, at: point) else { return false }
            }
            // Prefer actual membership, including minimized/hidden windows that are not on screen.
            // When metadata is absent, keep the existing bounded WindowServer visibility inference.
            switch filter.spaceScope {
            case .all: break
            case .visible: if window.isOnAnotherSpace { return false }
            case .notVisible:
                if let visible = window.spaceMembership?.isVisible {
                    if visible { return false }
                } else if window.zOrder != nil { return false }
            }
            if filter.currentScreenOnly, let displayID = context.displayID,
               let windowDisplay = window.displayID, windowDisplay != displayID { return false }
            return true
        }
        // Stable partition keeps the requested ordering within each of the two groups.
        let ordered = sorted(values, order: order)
        func isTrailing(_ window: SwitchableWindow) -> Bool {
            (filter.minimized == .atEnd && window.minimized) || (filter.hidden == .atEnd && window.hidden)
                || (filter.windowless == .atEnd && !window.isRealWindow)
        }
        let partitioned = ordered.filter { !isTrailing($0) } + ordered.filter { isTrailing($0) }
        var result = partitioned
        if !filter.separateTabs {
            var representatives: [String: String] = [:]
            for window in partitioned {
                guard let tab = window.nativeTab else { continue }
                if representatives[tab.groupID] == nil || tab.selected { representatives[tab.groupID] = window.id }
            }
            result = partitioned.filter { window in window.nativeTab.map { representatives[$0.groupID] == window.id } ?? true }
        }
        guard filter.grouping == .onePerApplication else { return result }
        // Keep separate running instances separate, including reused PIDs with a different launch date.
        struct ApplicationInstance: Hashable { let pid: Int32; let launchedAt: Date? }
        var seen = Set<ApplicationInstance>()
        return result.filter { seen.insert(.init(pid: $0.processID, launchedAt: $0.launchedAt)).inserted }
    }
}
