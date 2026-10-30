import CoreGraphics
import Foundation

/// Where a layout shortcut puts the focused window.
public enum WindowLayoutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, almostMaximize, center
    case nextDisplay, previousDisplay
    case restore

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: String(localized: "Sol yarı")
        case .rightHalf: String(localized: "Sağ yarı")
        case .topHalf: String(localized: "Üst yarı")
        case .bottomHalf: String(localized: "Alt yarı")
        case .topLeft: String(localized: "Sol üst çeyrek")
        case .topRight: String(localized: "Sağ üst çeyrek")
        case .bottomLeft: String(localized: "Sol alt çeyrek")
        case .bottomRight: String(localized: "Sağ alt çeyrek")
        case .leftThird: String(localized: "Sol üçte bir")
        case .centerThird: String(localized: "Orta üçte bir")
        case .rightThird: String(localized: "Sağ üçte bir")
        case .leftTwoThirds: String(localized: "Sol üçte iki")
        case .rightTwoThirds: String(localized: "Sağ üçte iki")
        case .maximize: String(localized: "Büyüt")
        case .almostMaximize: String(localized: "Neredeyse tam ekran")
        case .center: String(localized: "Ortala")
        case .nextDisplay: String(localized: "Sonraki ekrana taşı")
        case .previousDisplay: String(localized: "Önceki ekrana taşı")
        case .restore: String(localized: "Önceki konuma döndür")
        }
    }

    public enum Group: String, CaseIterable, Sendable { case halves, quarters, thirds, whole, displays }

    public var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .quarters
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: .thirds
        case .maximize, .almostMaximize, .center, .restore: .whole
        case .nextDisplay, .previousDisplay: .displays
        }
    }

    /// Default shortcuts: ⌃⌥ with arrows and nearby letters; ⌃⌥⌘ arrows move between displays.
    public var defaultShortcut: KeyCombo {
        let controlOption: KeyCombo.Modifiers = [.control, .option]
        let key: UInt16 = switch self {
        case .leftHalf: 123
        case .rightHalf: 124
        case .topHalf: 126
        case .bottomHalf: 125
        case .topLeft: 32 // U
        case .topRight: 34 // I
        case .bottomLeft: 38 // J
        case .bottomRight: 40 // K
        case .leftThird: 2 // D
        case .centerThird: 3 // F
        case .rightThird: 5 // G
        case .leftTwoThirds: 14 // E
        case .rightTwoThirds: 17 // T
        case .maximize: 36 // ↩
        case .almostMaximize: 0 // A
        case .center: 8 // C
        case .nextDisplay: 124
        case .previousDisplay: 123
        case .restore: 51 // ⌫
        }
        let isDisplayMove = self == .nextDisplay || self == .previousDisplay
        return KeyCombo(keyCode: key, modifiers: isDisplayMove ? controlOption.union(.command) : controlOption)
    }
}

public struct WindowLayoutSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Space left between windows and around the screen edge, in points.
    public var gap: Double = 0
    /// Pressing a half shortcut again cycles its width 1/2 → 2/3 → 1/3.
    public var cycleOnRepeat = true
    /// Actions without an entry use their default; a nil entry means the user switched that shortcut off.
    public var shortcuts: [WindowLayoutAction: KeyCombo?] = [:]

    public static let gapRange: ClosedRange<Double> = 0...24
    public static let storageKey = "MacPocket.windowLayout.settings"

    public init() {}

    public func shortcut(for action: WindowLayoutAction) -> KeyCombo? {
        if let entry = shortcuts[action] { return entry }
        return action.defaultShortcut
    }

    /// Actions that share a key combination with an earlier action; only the first one is registered.
    public var conflicts: [WindowLayoutAction] {
        var seen = Set<KeyCombo>()
        return WindowLayoutAction.allCases.filter { action in
            guard let combo = shortcut(for: action) else { return false }
            return !seen.insert(combo).inserted
        }
    }

    private enum CodingKeys: String, CodingKey { case enabled, gap, cycleOnRepeat, shortcuts, disabled }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        gap = min(max((try? container.decodeIfPresent(Double.self, forKey: .gap)) ?? 0, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        cycleOnRepeat = (try? container.decodeIfPresent(Bool.self, forKey: .cycleOnRepeat)) ?? true
        let stored = (try? container.decodeIfPresent([String: KeyCombo].self, forKey: .shortcuts)) ?? [:]
        for (name, combo) in stored {
            if let action = WindowLayoutAction(rawValue: name), combo.isValidGlobalShortcut { shortcuts[action] = .some(combo) }
        }
        let disabled = (try? container.decodeIfPresent([String].self, forKey: .disabled)) ?? []
        for name in disabled { if let action = WindowLayoutAction(rawValue: name) { shortcuts[action] = .some(nil) } }
    }

    /// Custom shortcuts and switched-off actions are stored separately: JSON has no Optional-of-Optional.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(gap, forKey: .gap)
        try container.encode(cycleOnRepeat, forKey: .cycleOnRepeat)
        var custom: [String: KeyCombo] = [:]
        var disabled: [String] = []
        for (action, combo) in shortcuts {
            if let combo { custom[action.rawValue] = combo } else { disabled.append(action.rawValue) }
        }
        try container.encode(custom, forKey: .shortcuts)
        try container.encode(disabled.sorted(), forKey: .disabled)
    }

    public static func load(from defaults: UserDefaults) -> WindowLayoutSettings {
        guard let data = defaults.data(forKey: storageKey) else { return WindowLayoutSettings() }
        return (try? JSONDecoder().decode(WindowLayoutSettings.self, from: data)) ?? WindowLayoutSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Frame arithmetic in AppKit screen coordinates (origin bottom-left, y up).
public enum WindowLayoutGeometry {
    /// Widths a repeated half/third press steps through.
    public static let cycle: [CGFloat] = [1.0 / 2.0, 2.0 / 3.0, 1.0 / 3.0]

    /// Target frame inside `area` (a screen's visible frame). `step` is the repeat count for cycling actions.
    /// `current` is needed for `center`. Returns nil for actions that aren't a region (display moves, restore).
    public static func frame(for action: WindowLayoutAction, in area: CGRect, gap: CGFloat, step: Int = 0,
                             current: CGRect? = nil) -> CGRect? {
        let half = cycle[step % cycle.count]
        let unit: CGRect
        switch action {
        case .leftHalf: unit = CGRect(x: 0, y: 0, width: half, height: 1)
        case .rightHalf: unit = CGRect(x: 1 - half, y: 0, width: half, height: 1)
        case .topHalf: unit = CGRect(x: 0, y: 1 - half, width: 1, height: half)
        case .bottomHalf: unit = CGRect(x: 0, y: 0, width: 1, height: half)
        case .topLeft: unit = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight: unit = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft: unit = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: unit = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .leftThird: unit = CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: unit = CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: unit = CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .leftTwoThirds: unit = CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: unit = CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .maximize: unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        case .almostMaximize: unit = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        case .center:
            guard let current else { return nil }
            let width = min(current.width, area.width - gap * 2), height = min(current.height, area.height - gap * 2)
            // Round the origin only: `.integral` would grow a half-point-aligned window by a point.
            return CGRect(x: (area.midX - width / 2).rounded(), y: (area.midY - height / 2).rounded(), width: width, height: height)
        case .nextDisplay, .previousDisplay, .restore:
            return nil
        }
        return place(unit, in: area, gap: gap)
    }

    /// Scales a unit rectangle into `area`, keeping `gap` at screen edges and between neighbouring windows.
    static func place(_ unit: CGRect, in area: CGRect, gap: CGFloat) -> CGRect {
        let inner = area.insetBy(dx: gap, dy: gap)
        var frame = CGRect(x: inner.minX + unit.minX * inner.width, y: inner.minY + unit.minY * inner.height,
                           width: unit.width * inner.width, height: unit.height * inner.height)
        // Shared edges get half a gap each, so two halves are exactly `gap` apart.
        if unit.minX > 0.001 { frame.origin.x += gap / 2; frame.size.width -= gap / 2 }
        if unit.maxX < 0.999 { frame.size.width -= gap / 2 }
        if unit.minY > 0.001 { frame.origin.y += gap / 2; frame.size.height -= gap / 2 }
        if unit.maxY < 0.999 { frame.size.height -= gap / 2 }
        return CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
    }

    /// Moves `frame` from one visible area to another, keeping its relative position and size.
    public static func move(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let scaleX = target.width / max(1, source.width), scaleY = target.height / max(1, source.height)
        let width = min(frame.width * scaleX, target.width), height = min(frame.height * scaleY, target.height)
        let x = target.minX + (frame.minX - source.minX) * scaleX
        let y = target.minY + (frame.minY - source.minY) * scaleY
        return CGRect(x: min(max(x, target.minX), target.maxX - width).rounded(), y: min(max(y, target.minY), target.maxY - height).rounded(),
                      width: width.rounded(), height: height.rounded())
    }

    /// Accessibility uses top-left-origin global coordinates; AppKit uses bottom-left of the primary screen.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether `action` should cycle given the previous press (same action, same window, within 1.5 s).
    public static func nextStep(previous: (action: WindowLayoutAction, step: Int, at: Date)?, action: WindowLayoutAction,
                                now: Date, cycling: Bool) -> Int {
        guard cycling, [.leftHalf, .rightHalf, .topHalf, .bottomHalf].contains(action),
              let previous, previous.action == action, now.timeIntervalSince(previous.at) < 1.5 else { return 0 }
        return previous.step + 1
    }
}
