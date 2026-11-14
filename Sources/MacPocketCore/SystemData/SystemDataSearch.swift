import Foundation

/// Search that finds Turkish names with plain letters: "kayit" finds "kayıt", "ISTANBUL" finds "İstanbul",
/// "cagri" finds "Çağrı", and a decomposed "Café" is found by "cafe". Every word of the query must appear.
public enum SystemDataSearch {
    /// Lowercase, accent-free, with the Turkish dotless ı and dotted İ folded to plain i.
    public static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    public static func matches(_ query: String, in haystacks: [String]) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let folded = haystacks.map(fold).joined(separator: "\n")
        return words.allSatisfy { folded.contains($0) }
    }

    public static func matches(_ query: String, item: SystemDataItem) -> Bool {
        matches(query, in: [item.title, item.detail, item.group.localizedTitle, item.projectPath ?? ""] + item.paths)
    }
}
