import Foundation

/// Global input preferences, captured at session start. Existing installations retain arrows;
/// Vim is opt-in. These do not change the opening shortcut or record global letter keys.
public struct SwitcherNavigationOptions: Equatable, Sendable {
    public static let arrowsKey = "switcher.arrowKeysEnabled"
    public static let vimKey = "switcher.vimKeysEnabled"
    public var arrows: Bool
    public var vim: Bool
    public init(arrows: Bool = true, vim: Bool = false) { self.arrows = arrows; self.vim = vim }
    public static func load(_ defaults: UserDefaults = .standard) -> Self {
        .init(arrows: defaults.object(forKey: arrowsKey) as? Bool ?? true,
              vim: defaults.object(forKey: vimKey) as? Bool ?? false)
    }
    /// Custom actions take precedence; report the actual keys they replace without clearing
    /// the user's bindings. Characters come from the active keyboard layout, not US positions.
    public func overriddenBindings(_ bindings: [SwitcherActionBinding], characters: [UInt16: String], shiftedCharacters: [UInt16: String] = [:]) -> [SwitcherActionBinding] {
        bindings.filter { binding in
            guard let code = binding.keyCode, binding.modifiers.isEmpty else { return false }
            let text = binding.shift ? shiftedCharacters[code] : characters[code]
            return (arrows && (123...126).contains(code))
                || (vim && (text == "/" || (!binding.shift && text.map { ["h","j","k","l"].contains($0) } == true)))
        }
    }
}

public enum SwitcherPanelKeyCommand: Equatable, Sendable {
    case action(SwitcherActiveAction)
    case move(backwards: Bool, count: Int)
    case row(backwards: Bool)
    /// Consume a reserved navigation key without changing selection/native focus or searching.
    case ignore
}

/// One precedence policy shared by the controller and tests. Uses logical Vim characters so
/// a non-US layout does not silently turn a different letter into a navigation key.
public enum SwitcherPanelInput {
    public static func command(keyCode: UInt16, characters: String, modifiers: SwitcherModifiers, shift: Bool,
                               held: SwitcherModifiers, isSearching: Bool,
                               options: SwitcherNavigationOptions, bindings: [SwitcherActionBinding]) -> SwitcherPanelKeyCommand? {
        if keyCode == SwitcherKeys.escape { return .action(.cancel) }
        if let action = SwitcherActionBindings.action(for: keyCode, modifiers: modifiers, shift: shift,
                                                      held: held, isSearching: isSearching, bindings: bindings) { return .action(action) }
        let effective = modifiers.subtracting(held)
        if keyCode == 76, effective.isEmpty, !shift,
           bindings.contains(where: { $0.action == .choose && $0.keyCode == 36 && $0.modifiers.isEmpty && !$0.shift }) { return .action(.choose) }
        if keyCode == SwitcherKeys.tab { return effective.isEmpty ? .move(backwards: shift, count: 1) : .ignore }
        if (123...126).contains(keyCode) {
            guard options.arrows, effective.isEmpty else { return .ignore }
            switch keyCode {
            case 123: return .move(backwards: true, count: 1)
            case 124: return .move(backwards: false, count: 1)
            case 125: return .row(backwards: false)
            default: return .row(backwards: true)
            }
        }
        guard options.vim, !isSearching, effective.isEmpty else { return nil }
        // Slash needs Shift on layouts such as Turkish Q. Its logical character remains
        // the search command; shifted letters remain ordinary text rather than Vim motion.
        if characters == "/" { return .action(.search) }
        guard !shift else { return nil }
        switch characters {
        case "h": return .move(backwards: true, count: 1)
        case "l": return .move(backwards: false, count: 1)
        case "j": return .row(backwards: false)
        case "k": return .row(backwards: true)
        default: return nil
        }
    }
}
