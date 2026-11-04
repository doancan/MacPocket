import Foundation

public enum CaseLanguage: String, CaseIterable, Identifiable, Sendable {
    case turkish, english
    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: self == .turkish ? "tr_TR" : "en_US_POSIX") }
    public var localizedTitle: String {
        self == .turkish ? String(localized: "Türkçe") : String(localized: "İngilizce")
    }
}

public enum CaseFormat: String, CaseIterable, Identifiable, Sendable {
    case upper, lower, title, sentence, toggle, alternating
    case camel, pascal, snake, constant, kebab, train, dot, path
    public var id: String { rawValue }
    public var usesWords: Bool {
        switch self {
        case .upper, .lower, .title, .sentence, .toggle, .alternating: false
        default: true
        }
    }
    public var localizedTitle: String {
        switch self {
        case .upper: String(localized: "Büyük harf")
        case .lower: String(localized: "Küçük harf")
        case .title: String(localized: "Başlık biçimi")
        case .sentence: String(localized: "Cümle biçimi")
        case .toggle: String(localized: "Ters harf durumu")
        case .alternating: String(localized: "Dönüşümlü harf")
        case .camel: String(localized: "camelCase")
        case .pascal: String(localized: "PascalCase")
        case .snake: String(localized: "snake_case")
        case .constant: String(localized: "CONSTANT_CASE")
        case .kebab: String(localized: "kebab-case")
        case .train: String(localized: "Train-Case")
        case .dot: String(localized: "dot.case")
        case .path: String(localized: "path/case")
        }
    }
}

public struct CaseOptions: Sendable, Equatable {
    public var language: CaseLanguage
    public var lineByLine: Bool
    public var keepBlankLines: Bool
    public var simplifyLatin: Bool
    public var splitAcronyms: Bool
    public var separateNumbers: Bool
    public var preserveAcronyms: Bool
    public var prefixNumericIdentifiers: Bool

    public init(language: CaseLanguage = .english, lineByLine: Bool = true, keepBlankLines: Bool = true,
                simplifyLatin: Bool = false, splitAcronyms: Bool = true, separateNumbers: Bool = false,
                preserveAcronyms: Bool = false, prefixNumericIdentifiers: Bool = true) {
        self.language = language; self.lineByLine = lineByLine; self.keepBlankLines = keepBlankLines
        self.simplifyLatin = simplifyLatin; self.splitAcronyms = splitAcronyms; self.separateNumbers = separateNumbers
        self.preserveAcronyms = preserveAcronyms; self.prefixNumericIdentifiers = prefixNumericIdentifiers
    }
}

public struct CasePreview: Sendable, Equatable, Identifiable {
    public let format: CaseFormat
    public let text: String
    public var id: CaseFormat { format }
}

public struct CaseTextStats: Sendable, Equatable {
    public let characters: Int
    public let words: Int
    public let lines: Int
}

public enum CaseConverterError: Error, LocalizedError, Equatable {
    case size, outputSize, transliteration
    public var errorDescription: String? {
        switch self {
        case .size: String(localized: "Harf dönüştürme girdisi en fazla 64 KiB olabilir. Daha küçük bir bölüm kullan.")
        case .outputSize: String(localized: "Toplu önizleme çok büyüdü. Daha küçük bir bölüm dönüştür.")
        case .transliteration: String(localized: "Latin harfleri sadeleştirilemedi. Sadeleştirme seçeneğini kapatıp yeniden dene.")
        }
    }
}

public enum CaseConverter {
    public static let maximumInputBytes = 64 * 1024
    private static let maximumOutputBytes = 4 * 1024 * 1024

    public static func previews(_ input: String, options: CaseOptions = CaseOptions()) throws -> [CasePreview] {
        try validate(input)
        var total = 0
        return try CaseFormat.allCases.map { format in
            try Task.checkCancellation()
            let text = try convert(input, to: format, options: options)
            total += text.utf8.count
            guard total <= maximumOutputBytes else { throw CaseConverterError.outputSize }
            return CasePreview(format: format, text: text)
        }
    }

    public static func statistics(_ input: String) -> CaseTextStats {
        var words = 0
        input.enumerateSubstrings(in: input.startIndex..<input.endIndex, options: .byWords) { _, _, _, _ in words += 1 }
        return .init(characters: input.count, words: words, lines: input.isEmpty ? 0 : splitLines(input).count)
    }

    public static func convert(_ input: String, to format: CaseFormat, options: CaseOptions = CaseOptions()) throws -> String {
        try validate(input)
        let normalized = input.precomposedStringWithCanonicalMapping
        let parts = options.lineByLine ? splitLines(normalized) : [(normalized, "")]
        var output = "", outputBytes = 0
        for (index, part) in parts.enumerated() {
            if index.isMultiple(of: 32) { try Task.checkCancellation() }
            if options.lineByLine, !options.keepBlankLines, part.0.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            var transformed = transform(part.0, to: format, options: options)
            if options.simplifyLatin {
                guard let plain = transformed.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) else { throw CaseConverterError.transliteration }
                transformed = plain
            }
            outputBytes += transformed.utf8.count + part.1.utf8.count
            guard outputBytes <= maximumOutputBytes else { throw CaseConverterError.outputSize }
            output += transformed + part.1
        }
        return output
    }

    private static func validate(_ input: String) throws {
        guard !input.isEmpty else { throw PracticalToolError.empty }
        guard input.utf8.count <= maximumInputBytes else { throw CaseConverterError.size }
    }

    private static func splitLines(_ input: String) -> [(String, String)] {
        var result: [(String, String)] = [], current = ""
        for character in input {
            if character.isNewline { result.append((current, String(character))); current = "" }
            else { current.append(character) }
        }
        result.append((current, ""))
        return result
    }

    private static func transform(_ input: String, to format: CaseFormat, options: CaseOptions) -> String {
        let locale = options.language.locale
        switch format {
        case .upper: return input.uppercased(with: locale)
        case .lower: return input.lowercased(with: locale)
        case .title: return input.capitalized(with: locale)
        case .sentence: return sentence(input, locale: locale)
        case .toggle:
            return input.reduce(into: "") { result, character in
                let value = String(character)
                result += character.isUppercase ? value.lowercased(with: locale) : character.isLowercase ? value.uppercased(with: locale) : value
            }
        case .alternating:
            var upper = false
            return input.reduce(into: "") { result, character in
                let value = String(character)
                guard character.isUppercase || character.isLowercase else { result += value; return }
                result += upper ? value.uppercased(with: locale) : value.lowercased(with: locale)
                upper.toggle()
            }
        default: break
        }
        let words = splitWords(input, options: options)
        func isAcronym(_ word: String) -> Bool {
            word.count > 1 && word.contains(where: \.isUppercase) && !word.contains(where: \.isLowercase)
        }
        func lower(_ word: String) -> String {
            options.preserveAcronyms && isAcronym(word) ? word : word.lowercased(with: locale)
        }
        func capital(_ word: String) -> String {
            if options.preserveAcronyms && isAcronym(word) { return word }
            let lowered = word.lowercased(with: locale)
            return String(lowered.prefix(1)).uppercased(with: locale) + lowered.dropFirst()
        }
        var text: String
        switch format {
        case .camel: text = words.enumerated().map { $0.offset == 0 ? $0.element.lowercased(with: locale) : capital($0.element) }.joined()
        case .pascal: text = words.map(capital).joined()
        case .snake: text = words.map(lower).joined(separator: "_")
        case .constant: text = words.map { $0.uppercased(with: locale) }.joined(separator: "_")
        case .kebab: text = words.map(lower).joined(separator: "-")
        case .train: text = words.map(capital).joined(separator: "-")
        case .dot: text = words.map(lower).joined(separator: ".")
        case .path: text = words.map(lower).joined(separator: "/")
        default: text = input
        }
        if options.prefixNumericIdentifiers, [.camel, .pascal, .snake, .constant].contains(format), text.first?.isNumber == true {
            text = "_" + text
        }
        return text
    }

    private static func splitWords(_ input: String, options: CaseOptions) -> [String] {
        let characters = Array(input)
        var words: [String] = [], word = ""
        for index in characters.indices {
            let current = characters[index]
            guard current.isLetter || current.isNumber else {
                if !word.isEmpty { words.append(word); word = "" }
                continue
            }
            if !word.isEmpty, index > 0 {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let lowerToUpper = (previous.isLowercase || previous.isNumber) && current.isUppercase
                let acronymEnd = options.splitAcronyms && previous.isUppercase && current.isUppercase && next?.isLowercase == true
                let numberBoundary = options.separateNumbers && previous.isNumber != current.isNumber
                if lowerToUpper || acronymEnd || numberBoundary { words.append(word); word = "" }
            }
            word.append(current)
        }
        if !word.isEmpty { words.append(word) }
        return words
    }

    /// Deliberate punctuation-based sentence casing, preserving layout and decimal points.
    private static func sentence(_ input: String, locale: Locale) -> String {
        let text = Array(input.lowercased(with: locale))
        var startsSentence = true, result = ""
        for index in text.indices {
            let character = text[index]
            if character.isLetter, startsSentence {
                result += String(character).uppercased(with: locale); startsSentence = false
            } else { result.append(character) }
            if character.isNumber { startsSentence = false }
            let decimalPoint = character == "." && index > 0 && index + 1 < text.count && text[index - 1].isNumber && text[index + 1].isNumber
            if character.isNewline || ("!?….".contains(character) && !decimalPoint) { startsSentence = true }
        }
        return result
    }
}
