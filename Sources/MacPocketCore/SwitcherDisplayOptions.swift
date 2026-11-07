import CoreGraphics
import Foundation

public enum SwitcherTitleMode: String, CaseIterable, Codable, Sendable {
    case standard, window, application, both
    public var localizedTitle: String {
        switch self {
        case .standard: String(localized: "Stile göre")
        case .window: String(localized: "Pencere başlığı")
        case .application: String(localized: "Uygulama adı")
        case .both: String(localized: "Başlık ve uygulama")
        }
    }
    public func labels(for window: SwitchableWindow, style: SwitcherStyle) -> (primary: String, secondary: String?) {
        let title = window.isRealWindow ? window.title : window.application
        switch self {
        case .application: return (window.application, nil)
        case .window: return (title, nil)
        case .both: return (title, title == window.application ? nil : window.application)
        case .standard: return (title, style == .titles ? window.application : nil)
        }
    }
}

public enum SwitcherTitleTruncation: String, CaseIterable, Codable, Sendable {
    case head, middle, tail
    public var localizedTitle: String {
        switch self {
        case .head: String(localized: "Baştan kısalt")
        case .middle: String(localized: "Ortadan kısalt")
        case .tail: String(localized: "Sondan kısalt")
        }
    }
}

public enum SwitcherScreenPolicy: String, CaseIterable, Codable, Sendable {
    case pointer, activeWindow, menuBar
    public var localizedTitle: String {
        switch self {
        case .pointer: String(localized: "Farenin bulunduğu ekran")
        case .activeWindow: String(localized: "Öndeki pencerenin ekranı")
        case .menuBar: String(localized: "Ana menü çubuğu ekranı")
        }
    }
    /// All frames and points must use the same coordinate system. Main/menu-bar display and
    /// active window are distinct: NSScreen.main alone cannot represent these three policies.
    public func displayID(screens: [(UInt32, CGRect)], pointer: CGPoint, activeWindowFrame: CGRect?, primaryDisplayID: UInt32?) -> UInt32? {
        let primary = screens.first { $0.0 == primaryDisplayID }?.0 ?? screens.first?.0
        let pointed = screens.first { $0.1.contains(pointer) }?.0 ?? primary
        switch self {
        case .pointer: return pointed
        case .menuBar: return primary
        case .activeWindow:
            guard let frame = activeWindowFrame, frame.width > 0, frame.height > 0,
                  [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { return pointed }
            return WindowFiltering.displayID(for: frame, among: screens) ?? pointed
        }
    }
}

public enum SwitcherSpaceBadge {
    public static func text(_ membership: WindowSpaceMembership?) -> String {
        guard let membership else { return "?" }
        guard let first = membership.spaces.first else { return "?" }
        return first.ordinal.formatted(.number) + (membership.spaces.count > 1 ? "+" : "") + (membership.unknownIDs.isEmpty ? "" : "?")
    }
}

public struct SwitcherMotionPlan: Equatable, Sendable {
    public let opening: TimeInterval
    public let closing: TimeInterval
    public let selection: TimeInterval
    public let preview: TimeInterval
    public init(presentation: SwitcherPresentation, reduceMotion: Bool) {
        opening = !reduceMotion && presentation.animateOpening ? 0.09 : 0
        closing = !reduceMotion && presentation.animateClosing ? 0.09 : 0
        selection = !reduceMotion && presentation.animateSelection ? 0.16 : 0
        preview = !reduceMotion && presentation.animatePreview ? 0.12 : 0
    }
}
