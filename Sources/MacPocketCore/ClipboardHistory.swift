import Foundation

// MARK: - Shortcut

/// A global key combination. Unlike switcher shortcuts, Shift is a regular modifier here.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let command = Modifiers(rawValue: 4)
        public static let shift = Modifiers(rawValue: 8)
    }

    /// Virtual key code (kVK_*).
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) { self.keyCode = keyCode; self.modifiers = modifiers }

    /// Carbon `RegisterEventHotKey` flags (cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000).
    public var carbonFlags: UInt32 {
        (modifiers.contains(.command) ? 0x0100 : 0) | (modifiers.contains(.shift) ? 0x0200 : 0)
            | (modifiers.contains(.option) ? 0x0800 : 0) | (modifiers.contains(.control) ? 0x1000 : 0)
    }

    public var displayName: String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "") + SwitcherKeys.name(for: keyCode)
    }

    /// A global shortcut needs ⌘, ⌃ or ⌥; Shift alone would swallow ordinary typing.
    public var isValidGlobalShortcut: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty && SwitcherKeys.isSupported(keyCode)
    }
}

// MARK: - Items

public struct ClipboardImageReference: Codable, Hashable, Sendable {
    /// File inside the history's image folder, named after the content hash.
    public let fileName: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int

    public init(fileName: String, pixelWidth: Int, pixelHeight: Int, byteCount: Int) {
        self.fileName = fileName; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.byteCount = byteCount
    }
}

public enum ClipboardContent: Codable, Hashable, Sendable {
    case text(String)
    case link(URL)
    case image(ClipboardImageReference)
    case files([URL])

    public enum Kind: String, CaseIterable, Codable, Sendable { case text, link, image, files }

    public var kind: Kind {
        switch self {
        case .text: .text
        case .link: .link
        case .image: .image
        case .files: .files
        }
    }

    /// Plain-text form for searching and for pasting without formatting.
    public var plainText: String? {
        switch self {
        case let .text(text): text
        case let .link(url): url.absoluteString
        case let .files(urls): urls.map(\.path).joined(separator: "\n")
        case .image: nil
        }
    }
}

public struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var content: ClipboardContent
    public var copiedAt: Date
    public var sourceBundleID: String?
    public var sourceName: String?
    public var pinned: Bool
    /// Times it was copied again or pasted from the history.
    public var useCount: Int

    public init(id: UUID = UUID(), content: ClipboardContent, copiedAt: Date, sourceBundleID: String? = nil,
                sourceName: String? = nil, pinned: Bool = false, useCount: Int = 1) {
        self.id = id; self.content = content; self.copiedAt = copiedAt; self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName; self.pinned = pinned; self.useCount = useCount
    }

    /// One-line summary for lists.
    public var title: String {
        switch content {
        case let .text(text):
            let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return String((line.map(String.init) ?? text).trimmingCharacters(in: .whitespaces).prefix(200))
        case let .link(url): return url.absoluteString
        case let .image(image): return String(localized: "Görsel \(image.pixelWidth)×\(image.pixelHeight)")
        case let .files(urls):
            return urls.count == 1 ? urls[0].lastPathComponent : String(localized: "\(urls.count) dosya")
        }
    }
}

// MARK: - Capture

/// What the pasteboard held at one change, already reduced to the best representation.
public struct ClipboardCapture: Equatable, Sendable {
    public var content: ClipboardContent
    public var sourceBundleID: String?
    public var sourceName: String?
    /// The writer marked it concealed or transient (nspasteboard.org): passwords, one-time codes, previews.
    public var isConcealed: Bool

    public init(content: ClipboardContent, sourceBundleID: String? = nil, sourceName: String? = nil, isConcealed: Bool = false) {
        self.content = content; self.sourceBundleID = sourceBundleID; self.sourceName = sourceName; self.isConcealed = isConcealed
    }

    /// Text that is exactly one web address becomes a link, so it can be cleaned and shown as one.
    public static func text(_ text: String, sourceBundleID: String? = nil, sourceName: String? = nil,
                            isConcealed: Bool = false) -> ClipboardCapture {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil {
            return ClipboardCapture(content: .link(url), sourceBundleID: sourceBundleID, sourceName: sourceName, isConcealed: isConcealed)
        }
        return ClipboardCapture(content: .text(text), sourceBundleID: sourceBundleID, sourceName: sourceName, isConcealed: isConcealed)
    }
}

// MARK: - Settings

public struct ClipboardSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var capacity = 200
    /// Unpinned items older than this are removed; nil keeps them until capacity pushes them out.
    public var retentionDays: Int? = 30
    public var keepImages = true
    /// Images above this size are not kept.
    public var maximumImageBytes = 15_000_000
    /// false: history lives only in memory and is gone when MacPocket quits.
    public var saveToDisk = true
    public var excludedBundleIDs: [String] = ClipboardSettings.defaultExcludedBundleIDs
    /// Strip tracking parameters from copied links on the pasteboard itself.
    public var cleanCopiedLinks = false
    public var extraTrackingParameters: [String] = []
    /// Empty the system clipboard this many minutes after the last copy; the history keeps the item.
    public var clearClipboardAfterMinutes: Int?
    public var clearClipboardOnSleepOrLock = false
    public var shortcut = KeyCombo(keyCode: 9, modifiers: [.command, .shift]) // ⇧⌘V
    /// Choosing an item pastes it into the app in front; otherwise it is only copied.
    public var pasteOnSelect = true

    public static let capacityChoices = [50, 100, 200, 500, 1000]
    public static let retentionChoices: [Int?] = [1, 7, 30, 90, nil]
    public static let clearAfterChoices: [Int?] = [nil, 1, 5, 15, 60]
    /// Password managers and the Keychain; most also mark their copies concealed.
    public static let defaultExcludedBundleIDs = ["com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password",
                                                  "com.agilebits.onepassword7", "com.bitwarden.desktop", "in.sinew.Enpass-Desktop"]
    /// Longer text (e.g. a whole log file) isn't kept.
    public static let maximumTextLength = 1_000_000

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, capacity, retentionDays, keepImages, maximumImageBytes, saveToDisk, excludedBundleIDs, cleanCopiedLinks
        case extraTrackingParameters, clearClipboardAfterMinutes, clearClipboardOnSleepOrLock, shortcut, pasteOnSelect
    }

    /// Missing fields keep their defaults, so stored settings survive future additions.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ClipboardSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        enabled = value(.enabled, defaults.enabled)
        capacity = min(max(value(.capacity, defaults.capacity), 10), 5000)
        // A stored null means "keep forever"; a missing key keeps the default.
        if container.contains(.retentionDays) {
            retentionDays = (try? container.decodeNil(forKey: .retentionDays)) == true ? nil : value(.retentionDays, defaults.retentionDays)
        }
        keepImages = value(.keepImages, defaults.keepImages)
        maximumImageBytes = value(.maximumImageBytes, defaults.maximumImageBytes)
        saveToDisk = value(.saveToDisk, defaults.saveToDisk)
        excludedBundleIDs = value(.excludedBundleIDs, defaults.excludedBundleIDs)
        cleanCopiedLinks = value(.cleanCopiedLinks, defaults.cleanCopiedLinks)
        extraTrackingParameters = value(.extraTrackingParameters, defaults.extraTrackingParameters)
        clearClipboardAfterMinutes = (try? container.decodeIfPresent(Int.self, forKey: .clearClipboardAfterMinutes)) ?? nil
        clearClipboardOnSleepOrLock = value(.clearClipboardOnSleepOrLock, defaults.clearClipboardOnSleepOrLock)
        let shortcut = value(.shortcut, defaults.shortcut)
        self.shortcut = shortcut.isValidGlobalShortcut ? shortcut : defaults.shortcut
        pasteOnSelect = value(.pasteOnSelect, defaults.pasteOnSelect)
    }

    /// Writes nil optionals as explicit nulls: synthesized encoding omits them, and a missing `retentionDays`
    /// decodes as the 30-day default, which would silently undo "keep forever".
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(keepImages, forKey: .keepImages)
        try container.encode(maximumImageBytes, forKey: .maximumImageBytes)
        try container.encode(saveToDisk, forKey: .saveToDisk)
        try container.encode(excludedBundleIDs, forKey: .excludedBundleIDs)
        try container.encode(cleanCopiedLinks, forKey: .cleanCopiedLinks)
        try container.encode(extraTrackingParameters, forKey: .extraTrackingParameters)
        try container.encode(clearClipboardAfterMinutes, forKey: .clearClipboardAfterMinutes)
        try container.encode(clearClipboardOnSleepOrLock, forKey: .clearClipboardOnSleepOrLock)
        try container.encode(shortcut, forKey: .shortcut)
        try container.encode(pasteOnSelect, forKey: .pasteOnSelect)
    }

    public static let storageKey = "MacPocket.clipboard.settings"

    public static func load(from defaults: UserDefaults) -> ClipboardSettings {
        guard let data = defaults.data(forKey: storageKey) else { return ClipboardSettings() }
        return (try? JSONDecoder().decode(ClipboardSettings.self, from: data)) ?? ClipboardSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

// MARK: - History rules

public struct ClipboardHistory: Codable, Equatable, Sendable {
    /// Newest first.
    public private(set) var items: [ClipboardItem]

    public init(items: [ClipboardItem] = []) { self.items = items }

    public enum RecordResult: Equatable, Sendable {
        case added(ClipboardItem.ID)
        /// The same content was already there; it moved to the top.
        case refreshed(ClipboardItem.ID)
        case ignored(IgnoreReason)
    }

    public enum IgnoreReason: Equatable, Sendable { case concealed, excludedApplication, empty, tooLarge, imagesOff }

    /// Adds a capture. Returns what happened and the image files no longer referenced (to delete).
    public mutating func record(_ capture: ClipboardCapture, at date: Date, settings: ClipboardSettings)
        -> (result: RecordResult, orphanedImages: [String]) {
        if capture.isConcealed { return (.ignored(.concealed), []) }
        if let source = capture.sourceBundleID, settings.excludedBundleIDs.contains(source) { return (.ignored(.excludedApplication), []) }
        switch capture.content {
        case let .text(text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (.ignored(.empty), []) }
            if text.count > ClipboardSettings.maximumTextLength { return (.ignored(.tooLarge), []) }
        case let .image(image):
            if !settings.keepImages { return (.ignored(.imagesOff), []) }
            if image.byteCount > settings.maximumImageBytes { return (.ignored(.tooLarge), []) }
        case let .files(urls):
            if urls.isEmpty { return (.ignored(.empty), []) }
        case .link:
            break
        }
        if let index = items.firstIndex(where: { $0.content == capture.content }) {
            var item = items.remove(at: index)
            item.copiedAt = date
            item.sourceBundleID = capture.sourceBundleID ?? item.sourceBundleID
            item.sourceName = capture.sourceName ?? item.sourceName
            item.useCount += 1
            items.insert(item, at: 0)
            return (.refreshed(item.id), [])
        }
        let item = ClipboardItem(content: capture.content, copiedAt: date, sourceBundleID: capture.sourceBundleID,
                                 sourceName: capture.sourceName)
        items.insert(item, at: 0)
        return (.added(item.id), enforceCapacity(settings.capacity))
    }

    /// Drops the oldest unpinned items beyond `capacity`. Pinned items never count against it.
    public mutating func enforceCapacity(_ capacity: Int) -> [String] {
        var unpinned = 0
        var removed: [ClipboardItem] = []
        items.removeAll { item in
            guard !item.pinned else { return false }
            unpinned += 1
            if unpinned > capacity { removed.append(item); return true }
            return false
        }
        return orphanedImages(after: removed)
    }

    /// Removes unpinned items copied before `days` ago.
    public mutating func prune(olderThan days: Int?, now: Date) -> [String] {
        guard let days else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var removed: [ClipboardItem] = []
        items.removeAll { item in
            guard !item.pinned, item.copiedAt < cutoff else { return false }
            removed.append(item)
            return true
        }
        return orphanedImages(after: removed)
    }

    public mutating func setPinned(_ pinned: Bool, for id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned = pinned
    }

    /// Marks an item used from the history and moves it to the top.
    public mutating func markUsed(_ id: ClipboardItem.ID, at date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.useCount += 1
        item.copiedAt = date
        items.insert(item, at: 0)
    }

    public mutating func replaceContent(of id: ClipboardItem.ID, with content: ClipboardContent) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].content = content
    }

    public mutating func remove(_ id: ClipboardItem.ID) -> [String] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        return orphanedImages(after: [items.remove(at: index)])
    }

    /// Clears the history; pinned items stay unless `includingPinned`.
    public mutating func clear(includingPinned: Bool) -> [String] {
        let removed = items.filter { includingPinned || !$0.pinned }
        items.removeAll { includingPinned || !$0.pinned }
        return orphanedImages(after: removed)
    }

    /// Image files referenced by `removed` and by no remaining item.
    private func orphanedImages(after removed: [ClipboardItem]) -> [String] {
        let remaining = Set(items.compactMap { if case let .image(image) = $0.content { image.fileName } else { nil } })
        let files = removed.compactMap { if case let .image(image) = $0.content { image.fileName } else { nil } }
        return Array(Set(files).subtracting(remaining)).sorted()
    }

    /// Pinned first, then newest. The query matches text, links, file names and the source app,
    /// ignoring case and diacritics ("istanbul" finds "İstanbul").
    public func search(_ query: String, kind: ClipboardContent.Kind? = nil) -> [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matches = items.filter { item in
            if let kind, item.content.kind != kind { return false }
            guard !needle.isEmpty else { return true }
            let haystack = [item.content.plainText, item.sourceName, item.title].compactMap { $0 }.joined(separator: "\n")
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || Self.fold(haystack).contains(Self.fold(needle))
        }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }

    /// Turkish dotted/dotless I fold to plain "i" so either spelling finds the other.
    private static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "i").replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - Link cleaning

/// Removes tracking parameters from web links. Rules are global names, name prefixes, and names that track
/// only on specific sites (where the same name elsewhere may be meaningful).
public struct LinkCleaner: Sendable {
    public static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
        "mc_cid", "mc_eid", "igshid", "igsh", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "vero_conv", "rb_clickid", "s_cid", "_openstat",
        "ref_src", "ref_url", "wickedid", "epik", "srsltid",
    ]
    public static let trackingPrefixes = ["utm_", "pk_", "piwik_", "matomo_", "mtm_"]
    /// Host suffix → parameters that track only there.
    public static let siteParameters: [String: Set<String>] = [
        "youtube.com": ["si", "feature", "pp"], "youtu.be": ["si", "feature"],
        "spotify.com": ["si", "context"], "instagram.com": ["igsh", "img_index"],
        "x.com": ["s", "t", "ref_src"], "twitter.com": ["s", "t", "ref_src"],
        "amazon.com": ["ref", "ref_", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pd_rd_i", "pf_rd_r", "pf_rd_p", "psc", "content-id", "th"],
        "amazon.com.tr": ["ref", "ref_", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pd_rd_i", "pf_rd_r", "pf_rd_p", "psc", "content-id", "th"],
        "linkedin.com": ["trk", "trackingId", "lipi", "midToken", "midSig", "trkEmail", "eid"],
        "trendyol.com": ["boutiqueId", "merchantId", "sav"], "hepsiburada.com": ["magaza", "wt_int"],
    ]

    public let extraParameters: Set<String>

    public init(extraParameters: [String] = []) {
        self.extraParameters = Set(extraParameters.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    /// The cleaned link, or nil when nothing was removed (or it isn't a web link).
    public func clean(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let host = components.host?.lowercased() ?? ""
        let siteRules = Self.siteParameters.filter { host == $0.key || host.hasSuffix("." + $0.key) }.flatMap(\.value)
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if Self.trackingParameters.contains(name) || extraParameters.contains(name) { return false }
            if Self.trackingPrefixes.contains(where: name.hasPrefix) { return false }
            if siteRules.contains(where: { $0.lowercased() == name }) { return false }
            return true
        }
        guard kept.count < items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url
    }
}

// MARK: - Archive

/// Reads and writes the history file. Files are created owner-only (0600 inside a 0700 folder):
/// clipboard contents can be private.
public struct ClipboardArchive: Sendable {
    public let directory: URL
    public var historyFile: URL { directory.appendingPathComponent("history.json") }
    public var imagesDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    public init(directory: URL) { self.directory = directory }

    public static var standard: ClipboardArchive {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ClipboardArchive(directory: base.appendingPathComponent("MacPocket/Clipboard", isDirectory: true))
    }

    public func load() throws -> ClipboardHistory {
        guard FileManager.default.fileExists(atPath: historyFile.path) else { return ClipboardHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClipboardHistory.self, from: Data(contentsOf: historyFile))
    }

    public func save(_ history: ClipboardHistory) throws {
        try prepareDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        try data.write(to: historyFile, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyFile.path)
    }

    /// Stores image data under its content name; an existing file with that name is the same image.
    public func storeImage(_ data: Data, named fileName: String) throws -> URL {
        try prepareDirectories()
        let url = imageURL(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return url
    }

    public func imageURL(_ fileName: String) -> URL {
        // Names are hashes we generated; reject anything else so a crafted history file can't point elsewhere.
        let safe = fileName.range(of: #"^[0-9a-f]{16,64}\.png$"#, options: .regularExpression) != nil ? fileName : "invalid.png"
        return imagesDirectory.appendingPathComponent(safe)
    }

    public func deleteImages(_ fileNames: [String]) {
        for name in fileNames { try? FileManager.default.removeItem(at: imageURL(name)) }
    }

    /// Removes the history file and every stored image.
    public func eraseAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func prepareDirectories() throws {
        for folder in [directory, imagesDirectory] where !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}
