import Foundation

/// Finds the first nonblank line without splitting every remaining line in a large clipboard entry.
enum ClipboardTextPreview {
    static func title(_ text: String) -> String {
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[start..<end].trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return String(line.prefix(200)) }
            guard end < text.endIndex else { break }
            start = text.index(after: end)
        }
        // Preserve the existing all-blank fallback, including its newline characters.
        return String(text.trimmingCharacters(in: .whitespaces).prefix(200))
    }
}
