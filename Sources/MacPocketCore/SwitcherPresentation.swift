import Foundation

public enum SwitcherTheme: String, CaseIterable, Codable, Sendable {
    case system, light, dark
    public var localizedTitle: String {
        switch self {
        case .system: String(localized: "Sistem")
        case .light: String(localized: "Açık")
        case .dark: String(localized: "Koyu")
        }
    }
}

public enum SwitcherReleaseBehavior: String, CaseIterable, Codable, Sendable {
    case choose, hold, search
    public var localizedTitle: String {
        switch self {
        case .choose: String(localized: "Seçili pencereye geç")
        case .hold: String(localized: "Paneli açık tut")
        case .search: String(localized: "Aramaya geç")
        }
    }
}

public enum SwitcherReleaseDecision: Equatable, Sendable {
    case choose, keepOpen, beginSearch
    public static func resolve(_ behavior: SwitcherReleaseBehavior, isSearching: Bool) -> Self {
        guard !isSearching else { return .keepOpen }
        switch behavior {
        case .choose: return .choose
        case .hold: return .keepOpen
        case .search: return .beginSearch
        }
    }
}

/// Resolved once at session start, so unrelated preference writes cannot change a running switch.
public struct SwitcherPresentation: Equatable, Sendable {
    public var style: SwitcherStyle = .thumbnails
    public var theme: SwitcherTheme = .system
    public var autoSize = true
    public var sizeScale: Double = 1
    public var previewSelected = false
    public var order: WindowSortOrder = .recent
    public var titleMode: SwitcherTitleMode = .standard
    public var truncation: SwitcherTitleTruncation = .tail
    public var screen: SwitcherScreenPolicy = .pointer
    public var showStatus: Bool = true
    public var showSpaces: Bool = false
    public var showBadges: Bool = true
    public var showActions: Bool = true
    public var showThumbnails: Bool = true
    public var openingDelayMilliseconds: Int = 110
    public var animateOpening: Bool = true
    public var animateClosing: Bool = false
    public var animateSelection: Bool = true
    public var animatePreview: Bool = false
    public var effectiveStyle: SwitcherStyle { style == .thumbnails && !showThumbnails ? .icons : style }
    public init() {}

    public static func load(_ defaults: UserDefaults = .standard) -> Self {
        var result = Self()
        result.style = SwitcherStyle(rawValue: defaults.string(forKey: "switcher.style") ?? "") ?? .thumbnails
        result.theme = SwitcherTheme(rawValue: defaults.string(forKey: "switcher.theme") ?? "") ?? .system
        result.autoSize = defaults.object(forKey: "switcher.autoSize") as? Bool ?? true
        result.sizeScale = boundedScale(defaults.object(forKey: "switcher.size") as? Double ?? 1)
        result.previewSelected = defaults.bool(forKey: "switcher.previewSelected")
        result.order = WindowSortOrder(rawValue: defaults.string(forKey: "switcher.sort") ?? "") ?? .recent
        result.titleMode = SwitcherTitleMode(rawValue: defaults.string(forKey: "switcher.titleMode") ?? "") ?? .standard
        result.truncation = SwitcherTitleTruncation(rawValue: defaults.string(forKey: "switcher.truncation") ?? "") ?? .tail
        result.screen = SwitcherScreenPolicy(rawValue: defaults.string(forKey: "switcher.screen") ?? "") ?? .pointer
        result.showStatus = defaults.object(forKey: "switcher.showStatus") as? Bool ?? true
        result.showSpaces = defaults.object(forKey: "switcher.showSpaces") as? Bool ?? false
        result.showBadges = defaults.object(forKey: "switcher.showBadges") as? Bool ?? true
        result.showActions = defaults.object(forKey: "switcher.showActions") as? Bool ?? true
        result.showThumbnails = defaults.object(forKey: "switcher.showThumbnails") as? Bool ?? true
        result.openingDelayMilliseconds = boundedDelay((defaults.object(forKey: "switcher.openingDelayMilliseconds") as? NSNumber)?.doubleValue ?? 110)
        result.animateOpening = defaults.object(forKey: "switcher.animateOpening") as? Bool ?? true
        result.animateClosing = defaults.object(forKey: "switcher.animateClosing") as? Bool ?? false
        result.animateSelection = defaults.object(forKey: "switcher.animateSelection") as? Bool ?? true
        result.animatePreview = defaults.object(forKey: "switcher.animatePreview") as? Bool ?? false
        return result
    }

    public static func boundedDelay(_ value: Double) -> Int { value.isFinite ? Int(min(900, max(0, value)).rounded()) : 110 }

    static func boundedScale(_ scale: Double) -> Double { scale.isFinite ? min(1.4, max(0.6, scale)) : 1 }
}

/// nil means follow the global preference, including later global changes; it is not a copied default.
public struct SwitcherPresentationOverrides: Codable, Hashable, Sendable {
    public var style: SwitcherStyle?
    public var theme: SwitcherTheme?
    public var autoSize: Bool?
    public var sizeScale: Double?
    public var previewSelected: Bool?
    public var order: WindowSortOrder?
    public var titleMode: SwitcherTitleMode?
    public var truncation: SwitcherTitleTruncation?
    public var screen: SwitcherScreenPolicy?
    public var showStatus: Bool?
    public var showSpaces: Bool?
    public var showBadges: Bool?
    public var showActions: Bool?
    public var showThumbnails: Bool?
    public var openingDelayMilliseconds: Int?
    public var animateOpening: Bool?
    public var animateClosing: Bool?
    public var animateSelection: Bool?
    public var animatePreview: Bool?
    public init() {}
    public var isEmpty: Bool { self == Self() }

    public func resolve(over global: SwitcherPresentation) -> SwitcherPresentation {
        var result = global
        if let style { result.style = style }
        if let theme { result.theme = theme }
        if let autoSize { result.autoSize = autoSize }
        if let sizeScale { result.sizeScale = SwitcherPresentation.boundedScale(sizeScale) }
        if let previewSelected { result.previewSelected = previewSelected }
        if let order { result.order = order }
        if let titleMode { result.titleMode = titleMode }
        if let truncation { result.truncation = truncation }
        if let screen { result.screen = screen }
        if let showStatus { result.showStatus = showStatus }
        if let showSpaces { result.showSpaces = showSpaces }
        if let showBadges { result.showBadges = showBadges }
        if let showActions { result.showActions = showActions }
        if let showThumbnails { result.showThumbnails = showThumbnails }
        if let openingDelayMilliseconds { result.openingDelayMilliseconds = SwitcherPresentation.boundedDelay(Double(openingDelayMilliseconds)) }
        if let animateOpening { result.animateOpening = animateOpening }
        if let animateClosing { result.animateClosing = animateClosing }
        if let animateSelection { result.animateSelection = animateSelection }
        if let animatePreview { result.animatePreview = animatePreview }
        return result
    }

    enum CodingKeys: String, CodingKey { case style, theme, autoSize, sizeScale, previewSelected, order, titleMode, truncation, screen, showStatus, showSpaces, showBadges, showActions, showThumbnails, openingDelayMilliseconds, animateOpening, animateClosing, animateSelection, animatePreview }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        style = try values.decodeIfPresent(String.self, forKey: .style).flatMap(SwitcherStyle.init(rawValue:))
        theme = try values.decodeIfPresent(String.self, forKey: .theme).flatMap(SwitcherTheme.init(rawValue:))
        autoSize = try values.decodeIfPresent(Bool.self, forKey: .autoSize)
        sizeScale = try values.decodeIfPresent(Double.self, forKey: .sizeScale).map(SwitcherPresentation.boundedScale)
        previewSelected = try values.decodeIfPresent(Bool.self, forKey: .previewSelected)
        order = try values.decodeIfPresent(String.self, forKey: .order).flatMap(WindowSortOrder.init(rawValue:))
        titleMode = try values.decodeIfPresent(String.self, forKey: .titleMode).flatMap(SwitcherTitleMode.init(rawValue:))
        truncation = try values.decodeIfPresent(String.self, forKey: .truncation).flatMap(SwitcherTitleTruncation.init(rawValue:))
        screen = try values.decodeIfPresent(String.self, forKey: .screen).flatMap(SwitcherScreenPolicy.init(rawValue:))
        showStatus = try values.decodeIfPresent(Bool.self, forKey: .showStatus)
        showSpaces = try values.decodeIfPresent(Bool.self, forKey: .showSpaces)
        showBadges = try values.decodeIfPresent(Bool.self, forKey: .showBadges)
        showActions = try values.decodeIfPresent(Bool.self, forKey: .showActions)
        showThumbnails = try values.decodeIfPresent(Bool.self, forKey: .showThumbnails)
        openingDelayMilliseconds = try values.decodeIfPresent(Double.self, forKey: .openingDelayMilliseconds).map(SwitcherPresentation.boundedDelay)
        animateOpening = try values.decodeIfPresent(Bool.self, forKey: .animateOpening)
        animateClosing = try values.decodeIfPresent(Bool.self, forKey: .animateClosing)
        animateSelection = try values.decodeIfPresent(Bool.self, forKey: .animateSelection)
        animatePreview = try values.decodeIfPresent(Bool.self, forKey: .animatePreview)
    }
}

/// Carbon and local NSEvent may deliver the same physical invocation. Different shortcuts must
/// never suppress one another even if their events are within the delivery tolerance.
public struct SwitcherInvocationDeduplicator: Sendable {
    private var last: (id: UUID, backwards: Bool, source: String, timestamp: TimeInterval)?
    public init() {}
    public mutating func accepts(id: UUID, backwards: Bool, source: String, timestamp: TimeInterval) -> Bool {
        if let last, last.id == id, last.backwards == backwards, last.source != source,
           abs(last.timestamp - timestamp) < 0.05 { return false }
        last = (id, backwards, source, timestamp)
        return true
    }
}
