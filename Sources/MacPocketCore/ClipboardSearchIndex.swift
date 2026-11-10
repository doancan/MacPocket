import Foundation

/// In-memory search documents. All text preparation and matching runs on this actor, away from the UI.
public actor ClipboardSearchIndex {
    private enum SearchText: Sendable {
        case ascii(Data)
        case unicode(String)

        init(_ folded: String) {
            // Keep one representation; other scripts retain canonical String matching.
            if folded.utf8.allSatisfy({ $0 < 128 }) { self = .ascii(Data(folded.utf8)) }
            else { self = .unicode(folded) }
        }

        func contains(_ needle: String, ascii: Data?) -> Bool {
            switch self {
            case let .ascii(bytes):
                guard let ascii else { return false }
                return bytes.range(of: ascii) != nil
            case let .unicode(text): return text.contains(needle)
            }
        }
    }

    private struct Document: Sendable {
        let content: ClipboardContent
        let sourceName: String?
        let text: SearchText
    }

    private var documents: [UUID: Document] = [:]
    private var revision: UInt64?
    private var locale = Locale.current.identifier
    private var preparation: Task<Void, Error>?
    private(set) var preparedDocumentCount = 0

    public init() {}

    /// Monotonic revisions prevent an older panel request from replacing a newer history snapshot.
    public func prepare(_ history: ClipboardHistory, revision requested: UInt64) async throws {
        if let revision, requested < revision { throw CancellationError() }
        let currentLocale = Locale.current.identifier
        if revision != requested || preparation == nil || locale != currentLocale {
            preparation?.cancel()
            revision = requested
            if locale != currentLocale { documents = [:]; locale = currentLocale }
            let liveIDs = Set(history.items.map(\.id))
            documents = documents.filter { liveIDs.contains($0.key) }
            preparation = Task { try await self.build(history, revision: requested) }
        }
        try await preparation!.value
        try Task.checkCancellation()
        guard revision == requested else { throw CancellationError() }
    }

    private func build(_ history: ClipboardHistory, revision requested: UInt64) async throws {
        for (offset, item) in history.items.enumerated() {
            try Task.checkCancellation()
            guard revision == requested else { throw CancellationError() }
            if documents[item.id]?.content != item.content || documents[item.id]?.sourceName != item.sourceName {
                let text = [item.content.plainText, item.sourceName, item.title].compactMap { $0 }.joined(separator: "\n")
                documents[item.id] = Document(content: item.content, sourceName: item.sourceName, text: SearchText(Self.fold(text)))
                preparedDocumentCount += 1
            }
            // Keep completed documents when a newer snapshot interrupts preparation.
            if offset.isMultiple(of: 8) { await Task.yield() }
        }
    }

    public func search(_ query: String, kind: ClipboardContent.Kind? = nil,
                       in history: ClipboardHistory, revision requested: UInt64) async throws -> [ClipboardItem] {
        try await prepare(history, revision: requested)
        let originalNeedle = query.trimmingCharacters(in: .whitespaces)
        let needle = Self.fold(originalNeedle)
        let asciiNeedle = needle.utf8.allSatisfy { $0 < 128 } ? Data(needle.utf8) : nil
        // Foundation also accepts partial case-fold expansions in a non-ASCII query (e.g. ß).
        // Preserve that comparison on cache misses without retaining a second full-text document.
        let needsFoundationComparison = !originalNeedle.utf8.allSatisfy { $0 < 128 }
        var pinned: [ClipboardItem] = [], others: [ClipboardItem] = []
        for (offset, item) in history.items.enumerated() {
            try Task.checkCancellation()
            guard revision == requested else { throw CancellationError() }
            if kind == nil || item.content.kind == kind {
                var matches = originalNeedle.isEmpty
                    || (!needle.isEmpty && documents[item.id]?.text.contains(needle, ascii: asciiNeedle) == true)
                if !matches, needsFoundationComparison {
                    let text = [item.content.plainText, item.sourceName, item.title].compactMap { $0 }.joined(separator: "\n")
                    matches = text.range(of: originalNeedle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
                if matches {
                    if item.pinned { pinned.append(item) } else { others.append(item) }
                }
            }
            if offset.isMultiple(of: 32) { await Task.yield() }
        }
        return pinned + others
    }

    private static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "i").replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    var documentCount: Int { documents.count }
}
