import Foundation

/// Text that replaces an abbreviation as it is typed (";imza" → a signature, ";tarih" → today's date).
public struct Snippet: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    /// What to type; at least 2 characters so ordinary typing doesn't trigger it.
    public var abbreviation: String
    /// The replacement; may contain {date}, {time}, {datetime}, {weekday}, {clipboard}.
    public var expansion: String
    public var enabled = true

    public init(id: UUID = UUID(), abbreviation: String, expansion: String, enabled: Bool = true) {
        self.id = id; self.abbreviation = abbreviation; self.expansion = expansion; self.enabled = enabled
    }

    public var isValid: Bool { abbreviation.count >= 2 && !abbreviation.contains(where: \.isWhitespace) && !expansion.isEmpty }
}

public struct SnippetSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var snippets: [Snippet] = [
        Snippet(abbreviation: ";tarih", expansion: "{date}"),
        Snippet(abbreviation: ";saat", expansion: "{time}"),
    ]
    /// Apps where abbreviations never expand (password managers, terminals by choice).
    public var excludedBundleIDs: [String] = ["com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password"]
    public static let storageKey = "MacPocket.snippets.settings"

    public init() {}

    public static func load(from defaults: UserDefaults) -> SnippetSettings {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(SnippetSettings.self, from: $0) } ?? SnippetSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    /// Abbreviations used by more than one enabled snippet; only the first one expands.
    public var duplicates: Set<String> {
        var seen = Set<String>(), result = Set<String>()
        for snippet in snippets where snippet.enabled && snippet.isValid {
            if !seen.insert(snippet.abbreviation).inserted { result.insert(snippet.abbreviation) }
        }
        return result
    }
}

/// Watches typed characters and reports when an abbreviation has just been completed.
public struct SnippetMatcher: Sendable {
    private var buffer = ""
    private let limit: Int

    public init(longestAbbreviation: Int = 32) { limit = max(2, longestAbbreviation) }

    /// Feeds one typed character; returns the snippet whose abbreviation now ends the input. The longest match
    /// wins, so ";tarihsaat" isn't cut short by ";tarih".
    public mutating func type(_ character: Character, snippets: [Snippet]) -> Snippet? {
        buffer.append(character)
        if buffer.count > limit { buffer.removeFirst(buffer.count - limit) }
        let match = snippets.filter { $0.enabled && $0.isValid && buffer.hasSuffix($0.abbreviation) }
            .max { $0.abbreviation.count < $1.abbreviation.count }
        if match != nil { buffer = "" }
        return match
    }

    public mutating func deleteBackward() { if !buffer.isEmpty { buffer.removeLast() } }

    /// Arrow keys, clicks, shortcuts and app switches: what follows is no longer one word.
    public mutating func reset() { buffer = "" }
}

public enum SnippetExpander {
    private static let variables = try? NSRegularExpression(pattern: #"\{(?:date|time|datetime|weekday|clipboard)\}"#)
    /// Replaces variables. Unknown {words} are left as typed.
    public static func expand(_ template: String, now: Date, clipboard: String?, locale: Locale, timeZone: TimeZone = .current) -> String {
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(pattern)
            return formatter.string(from: now)
        }
        let values: [String: String] = [
            "{date}": format("ddMMyyyy"),
            "{time}": format("HHmm"),
            "{datetime}": format("ddMMyyyyHHmm"),
            "{weekday}": format("EEEE"),
            "{clipboard}": clipboard ?? "",
        ]
        // Match only the original template: clipboard text containing {date}, for example, stays literal.
        // Replacing dictionary keys one by one made this depend on the dictionary's iteration order.
        guard let variables else { return template }
        let source = template as NSString
        let output = NSMutableString(string: template)
        for match in variables.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            if let value = values[source.substring(with: match.range)] { output.replaceCharacters(in: match.range, with: value) }
        }
        return output as String
    }
}
