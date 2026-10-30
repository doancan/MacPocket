import Foundation

// MARK: - Steps

public enum MacroAction: Codable, Hashable, Sendable {
    /// Press a key combination.
    case keystroke(KeyCombo)
    /// Type text as if from the keyboard (any Unicode, independent of the keyboard layout).
    case text(String)
    case delay(milliseconds: Int)
    case openApplication(bundleID: String)
    /// A web address, a file or another app's URL scheme.
    case openURL(URL)
    case appleScript(String)
    /// An Apple Shortcuts shortcut, by name.
    case shortcut(name: String)
    /// A command run with zsh, the user's own; stopped after `MacroRunLimits.shellTimeout`.
    case shell(command: String)

    public enum Kind: String, CaseIterable, Sendable {
        case keystroke, text, delay, openApplication, openURL, appleScript, shortcut, shell
    }

    public var kind: Kind {
        switch self {
        case .keystroke: .keystroke
        case .text: .text
        case .delay: .delay
        case .openApplication: .openApplication
        case .openURL: .openURL
        case .appleScript: .appleScript
        case .shortcut: .shortcut
        case .shell: .shell
        }
    }

    /// A blank step of each kind for the editor's "Add step" menu.
    public static func template(_ kind: Kind) -> MacroAction {
        switch kind {
        case .keystroke: .keystroke(KeyCombo(keyCode: 8, modifiers: [.command])) // ⌘C
        case .text: .text("")
        case .delay: .delay(milliseconds: 500)
        case .openApplication: .openApplication(bundleID: "com.apple.finder")
        case .openURL: .openURL(URL(string: "https://www.apple.com")!)
        case .appleScript: .appleScript("display notification \"MacPocket\"")
        case .shortcut: .shortcut(name: "")
        case .shell: .shell(command: "")
        }
    }

    /// Steps that can't run as they are (empty text, unusable delay…).
    public var problem: String? {
        switch self {
        case let .keystroke(combo): SwitcherKeys.isSupported(combo.keyCode) ? nil : String(localized: "Desteklenmeyen tuş")
        case let .text(text): text.isEmpty ? String(localized: "Yazılacak metin boş") : nil
        case let .delay(milliseconds): (MacroRunLimits.delayRange).contains(milliseconds) ? nil : String(localized: "Bekleme 0–60 sn arası olmalı")
        case let .openApplication(bundleID): bundleID.isEmpty ? String(localized: "Uygulama seçilmedi") : nil
        case let .openURL(url): url.scheme == nil ? String(localized: "Geçersiz adres") : nil
        case let .appleScript(source): source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Betik boş") : nil
        case let .shortcut(name): name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Kestirme adı boş") : nil
        case let .shell(command): command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Komut boş") : nil
        }
    }
}

public struct MacroStep: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var action: MacroAction

    public init(id: UUID = UUID(), _ action: MacroAction) { self.id = id; self.action = action }
}

public enum MacroRunLimits {
    public static let delayRange = 0...60_000
    public static let repeatRange = 1...100
    public static let shellTimeout: TimeInterval = 30
    /// A recorded pause longer than this becomes a delay step.
    public static let recordedPauseThreshold: TimeInterval = 0.8
}

// MARK: - Macros

public struct Macro: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var symbol = "wand.and.stars"
    public var steps: [MacroStep] = []
    public var trigger: KeyCombo?
    /// Empty: everywhere. Otherwise the trigger works only while one of these apps is in front.
    public var applications: [String] = []
    public var repeatCount = 1
    public var enabled = true

    public init(id: UUID = UUID(), name: String, steps: [MacroStep] = [], trigger: KeyCombo? = nil, applications: [String] = [],
                repeatCount: Int = 1, enabled: Bool = true) {
        self.id = id; self.name = name; self.steps = steps; self.trigger = trigger; self.applications = applications
        self.repeatCount = repeatCount; self.enabled = enabled
    }

    public var isGlobal: Bool { applications.isEmpty }

    /// Every step in run order, repeats expanded.
    public var plan: [MacroAction] {
        let count = min(max(repeatCount, MacroRunLimits.repeatRange.lowerBound), MacroRunLimits.repeatRange.upperBound)
        return Array(repeating: steps.map(\.action), count: count).flatMap { $0 }
    }

    public var problems: [String] { steps.compactMap(\.action.problem) }
}

public struct MacroLibrary: Codable, Equatable, Sendable {
    public var macros: [Macro] = []

    public init(macros: [Macro] = []) { self.macros = macros }

    /// The macro a trigger runs with `frontmost` in front: an app-specific macro wins over a global one.
    public func macro(for combo: KeyCombo, frontmost: String?) -> Macro? {
        let candidates = macros.filter { $0.enabled && $0.trigger == combo && !$0.steps.isEmpty }
        if let frontmost, let specific = candidates.first(where: { $0.applications.contains(frontmost) }) { return specific }
        return candidates.first(where: \.isGlobal)
    }

    /// Triggers the tap must watch.
    public var triggers: Set<KeyCombo> { Set(macros.filter(\.enabled).compactMap(\.trigger)) }

    /// Macros whose trigger overlaps an earlier macro's in the same scope (both global, or a shared app).
    public var conflicts: Set<Macro.ID> {
        var result = Set<Macro.ID>()
        let enabled = macros.filter { $0.enabled && $0.trigger != nil }
        for (index, macro) in enabled.enumerated() {
            for earlier in enabled[..<index] where earlier.trigger == macro.trigger {
                let overlap = (earlier.isGlobal && macro.isGlobal) || !Set(earlier.applications).isDisjoint(with: macro.applications)
                if overlap { result.insert(macro.id) }
            }
        }
        return result
    }

    public func search(_ query: String) -> [Macro] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let enabled = macros.filter { $0.enabled && !$0.steps.isEmpty }
        guard !needle.isEmpty else { return enabled }
        return enabled.filter { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

// MARK: - Recording

/// One key press captured while recording.
public struct RecordedKey: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: KeyCombo.Modifiers
    /// What the press typed, if it typed something printable.
    public let characters: String?
    public let time: TimeInterval

    public init(keyCode: UInt16, modifiers: KeyCombo.Modifiers, characters: String?, time: TimeInterval) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.characters = characters; self.time = time
    }
}

public enum MacroRecorder {
    /// Turns raw presses into steps: runs of plain typing become one text step, presses with ⌘, ⌃ or ⌥ and
    /// special keys become keystrokes, and pauses longer than the threshold become delays.
    public static func steps(from keys: [RecordedKey], keepPauses: Bool = true) -> [MacroAction] {
        var actions: [MacroAction] = []
        var text = ""
        var previous: TimeInterval?
        func flush() {
            if !text.isEmpty { actions.append(.text(text)); text = "" }
        }
        for key in keys {
            if keepPauses, let previous, key.time - previous > MacroRunLimits.recordedPauseThreshold {
                flush()
                actions.append(.delay(milliseconds: min(MacroRunLimits.delayRange.upperBound, Int(((key.time - previous) * 1000).rounded()))))
            }
            previous = key.time
            let commanding = !key.modifiers.intersection([.command, .control, .option]).isEmpty
            if !commanding, let characters = key.characters, !characters.isEmpty,
               characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                text += characters
            } else {
                flush()
                actions.append(.keystroke(KeyCombo(keyCode: key.keyCode, modifiers: key.modifiers)))
            }
        }
        flush()
        return actions
    }
}

// MARK: - Storage

/// The macro file: owner-only, in Application Support, also used for export and import.
public struct MacroArchive: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }

    public static var standard: MacroArchive {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MacroArchive(file: base.appendingPathComponent("MacPocket/Macros/library.json"))
    }

    public func load() throws -> MacroLibrary {
        guard FileManager.default.fileExists(atPath: file.path) else { return MacroLibrary() }
        return try JSONDecoder().decode(MacroLibrary.self, from: Data(contentsOf: file))
    }

    public func save(_ library: MacroLibrary) throws {
        let folder = file.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Imported macros get fresh identities so importing the same file twice doesn't create clashing IDs.
    public static func importing(_ data: Data) throws -> [Macro] {
        try JSONDecoder().decode(MacroLibrary.self, from: data).macros.map { macro in
            var copy = macro
            copy.id = UUID()
            copy.steps = macro.steps.map { MacroStep($0.action) }
            return copy
        }
    }
}
