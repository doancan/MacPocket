import Foundation

public struct CommandSearchEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case tool, action, application, window, clipboard }
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: Kind
    private let normalizedTitle: String
    private let normalizedText: String

    public init(id: String, title: String, subtitle: String = "", keywords: String = "", kind: Kind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        normalizedTitle = CommandSearch.normalize(String(title.prefix(512)))
        normalizedText = CommandSearch.normalize(String((title + " " + subtitle + " " + keywords).prefix(4096)))
    }

    fileprivate func score(query: String, tokens: [String]) -> Int? {
        guard !query.isEmpty else { return 0 }
        var score = 0
        for token in tokens {
            if normalizedTitle == token { score += 100 }
            else if normalizedTitle.hasPrefix(token) { score += 80 }
            else if normalizedTitle.contains(" " + token) { score += 60 }
            else if normalizedTitle.contains(token) { score += 40 }
            else if normalizedText.contains(token) { score += 10 }
            else { return nil }
        }
        if normalizedTitle == query { score += 1000 }
        else if normalizedTitle.hasPrefix(query) { score += 500 }
        return score
    }
}

/// Search tolerates Turkish keyboard variants without changing the text shown or copied to the user.
public enum CommandSearch {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func results(_ entries: [CommandSearchEntry], query: String, kind: CommandSearchEntry.Kind? = nil,
                               recent: [String] = [], pinned: Set<String> = [], limit: Int = 80) -> [CommandSearchEntry] {
        guard query.prefix(257).count <= 256 else { return [] }
        let query = normalize(query)
        let words = query.split(separator: " ")
        guard words.count <= 12 else { return [] }
        let tokens = words.map(String.init)
        let recency = Dictionary(recent.prefix(30).enumerated().map { ($0.element, 30 - $0.offset) }, uniquingKeysWith: max)
        var seen: Set<String> = []
        return entries.enumerated().compactMap { index, entry -> (Int, Int, CommandSearchEntry)? in
            guard kind == nil || kind == entry.kind, seen.insert(entry.id).inserted,
                  let score = entry.score(query: query, tokens: tokens) else { return nil }
            return (score + (pinned.contains(entry.id) ? 35 : 0) + (recency[entry.id] ?? 0), index, entry)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }
            .prefix(max(0, min(limit, 200))).map(\.2)
    }
}

public enum ParameterCommand: Equatable, Sendable {
    case brightness(Int)
    case keepAwake(minutes: Int)

    /// Only complete, bounded commands are executable; text is never passed to a shell.
    public static func parse(_ input: String) -> ParameterCommand? {
        guard input.utf8.count <= 1024 else { return nil }
        let query = CommandSearch.normalize(input)
        let prefixes: [(String, Bool)] = [("parlaklik ", true), ("brightness ", true),
                                         ("uyanik tut ", false), ("keep awake ", false), ("awake ", false)]
        for (prefix, brightness) in prefixes where query.hasPrefix(prefix) {
            var argument = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let suffixes = brightness ? ["%"] : ["dakika", "minutes", "minute", "min", "dk"]
            for suffix in suffixes where argument.hasSuffix(suffix) { argument.removeLast(suffix.count); break }
            argument = argument.trimmingCharacters(in: .whitespaces)
            guard !argument.isEmpty, argument.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(argument) else { return nil }
            if brightness { return (0...100).contains(value) ? .brightness(value) : nil }
            return (1...1440).contains(value) ? .keepAwake(minutes: value) : nil
        }
        return nil
    }
}
