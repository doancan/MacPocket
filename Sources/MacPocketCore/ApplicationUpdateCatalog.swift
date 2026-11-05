import Foundation

public enum ApplicationUpdateSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case homebrew, appStore, sparkle
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .homebrew: String(localized: "Homebrew")
        case .appStore: String(localized: "App Store")
        case .sparkle: String(localized: "Uygulama içi")
        }
    }
}

public struct ApplicationUpdateSettings: Codable, Equatable, Sendable {
    public var sources: Set<ApplicationUpdateSource> = [.homebrew]
    public var includePrereleases = false
    public var country = Locale.current.region?.identifier ?? "TR"
    public init() {}
    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: "MacPocket.applicationUpdateSources"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    public func save(to defaults: UserDefaults) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "MacPocket.applicationUpdateSources") } }
}

public enum ApplicationUpdateError: LocalizedError {
    case invalidURL, tooLarge, malformed, http(Int), country
    public var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "Güncelleme kaynağı geçerli bir HTTPS adresi değil.")
        case .tooLarge: String(localized: "Güncelleme listesi boyut sınırını aşıyor.")
        case .malformed: String(localized: "Güncelleme listesi okunamadı.")
        case .http(let code): String(localized: "Güncelleme kaynağı HTTP \(code) yanıtı verdi.")
        case .country: String(localized: "App Store için iki harfli geçerli bir ülke kodu gir.")
        }
    }
}

public enum ApplicationUpdateURL {
    public static func valid(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil && url.absoluteString.utf8.count <= 8192
    }
    public static func lookup(bundleIDs: [String], country: String) throws -> URL {
        let country = country.uppercased()
        guard country.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil,
              Locale.Region.isoRegions.contains(where: { $0.identifier == country }) else { throw ApplicationUpdateError.country }
        guard !bundleIDs.isEmpty, bundleIDs.count <= 20, bundleIDs.allSatisfy(validBundleID) else { throw ApplicationUpdateError.malformed }
        var url = URLComponents(string: "https://itunes.apple.com/lookup")!
        url.queryItems = [.init(name: "bundleId", value: bundleIDs.joined(separator: ",")), .init(name: "entity", value: "desktopSoftware"), .init(name: "country", value: country.lowercased())]
        return url.url!
    }
    public static func validBundleID(_ id: String) -> Bool {
        id.utf8.count <= 255 && id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]+$"#, options: .regularExpression) != nil && !id.contains("..")
    }
}

public struct ApplicationUpdateRelease: Equatable, Sendable {
    public let version: String
    public let displayVersion: String
    public let channel: String?
    public let minimumOS: String?
    public let maximumOS: String?
    public let hardware: String?
    public let storeID: Int64?
    public var prerelease: Bool {
        channel?.isEmpty == false || displayVersion.range(of: #"(?:alpha|beta|preview|nightly|dev|rc)[ ._-]*[0-9]*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    public func supports(os: String, architecture: String, compare: (String, String) -> ComparisonResult) -> Bool {
        if let minimumOS, compare(os, minimumOS) == .orderedAscending { return false }
        if let maximumOS, compare(os, maximumOS) == .orderedDescending { return false }
        if let hardware, hardware != architecture { return false }
        return true
    }
}

public enum AppStoreUpdateCatalog {
    /// Exact bundle identity and macOS kind prevent matching an iOS edition or similarly named app.
    public static func decode(_ data: Data, requested: Set<String>) throws -> [String: ApplicationUpdateRelease] {
        guard data.count <= 2_097_152 else { throw ApplicationUpdateError.tooLarge }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = object["resultCount"] as? Int, let rows = object["results"] as? [[String: Any]], count == rows.count else { throw ApplicationUpdateError.malformed }
        var result: [String: ApplicationUpdateRelease] = [:]
        let requested = Set(requested.map { $0.lowercased() })
        for row in rows {
            guard row["kind"] as? String == "mac-software", let id = row["bundleId"] as? String, requested.contains(id.lowercased()),
                  let version = row["version"] as? String, !version.isEmpty, version.utf8.count <= 128,
                  let storeID = row["trackId"] as? Int64, storeID > 0 else { continue }
            result[id.lowercased()] = .init(version: version, displayVersion: version, channel: nil, minimumOS: row["minimumOsVersion"] as? String, maximumOS: nil, hardware: nil, storeID: storeID)
        }
        return result
    }
}

public enum SparkleUpdateCatalog {
    public static func decode(_ data: Data) throws -> [ApplicationUpdateRelease] {
        guard data.count <= 2_097_152 else { throw ApplicationUpdateError.tooLarge }
        let prefix = Array(data.prefix(4))
        let encoding: String.Encoding
        if prefix.starts(with: [0xFF, 0xFE]) || prefix.starts(with: [0xFE, 0xFF]) { encoding = .utf16 }
        else if prefix.starts(with: [0x3C, 0]) { encoding = .utf16LittleEndian }
        else if prefix.starts(with: [0, 0x3C]) { encoding = .utf16BigEndian }
        else { encoding = .utf8 }
        guard let text = String(data: data, encoding: encoding), !text.contains("\0"),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw ApplicationUpdateError.malformed }
        let delegate = AppcastParser(), parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, delegate.rootIsRSS else { throw ApplicationUpdateError.malformed }
        return delegate.releases
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    var releases: [ApplicationUpdateRelease] = []
    var invalid = false, rootIsRSS = false
    private var depth = 0, itemDepth: Int?, deltasDepth: Int?
    private var fields: [String: String] = [:], enclosure: [String: String] = [:]
    private var field: String?, text = ""
    private var namespaces: [String: [String]] = [:]
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) { namespaces[prefix, default: []].append(namespaceURI) }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = namespaces[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        if depth > 32 || releases.count >= 1000 { invalid = true; parser.abortParsing(); return }
        if depth == 1 { rootIsRSS = name == "rss" }
        if name == "item", (namespaceURI ?? "").isEmpty, itemDepth == nil { itemDepth = depth; fields = [:]; enclosure = [:] }
        guard let itemDepth else { return }
        if name == "deltas", namespaceURI == Self.sparkle { deltasDepth = depth }
        if depth == itemDepth + 1, name == "enclosure", (namespaceURI ?? "").isEmpty, deltasDepth == nil {
            enclosure = [:]
            for (key, value) in attributes {
                let parts = key.split(separator: ":", maxSplits: 1)
                if parts.count == 1 { enclosure[key] = value }
                else if namespaces[String(parts[0])]?.last == Self.sparkle { enclosure["sparkle:" + parts[1]] = value }
            }
        }
        if depth == itemDepth + 1, namespaceURI == Self.sparkle, ["version", "shortVersionString", "minimumSystemVersion", "maximumSystemVersion", "hardwareRequirements", "channel"].contains(name) { field = name; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string; if text.utf8.count > 1024 { invalid = true; parser.abortParsing() } }
    }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { if let value = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: value) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        if let field, field == name, namespaceURI == Self.sparkle { fields[field] = text.trimmingCharacters(in: .whitespacesAndNewlines); self.field = nil }
        if deltasDepth == depth { deltasDepth = nil }
        guard let itemDepth, depth == itemDepth, name == "item" else { return }
        defer { self.itemDepth = nil }
        let version = fields["version"] ?? enclosure["sparkle:version"] ?? ""
        let os = enclosure["sparkle:os"] ?? "macos"
        guard !version.isEmpty, version.utf8.count <= 128, ["macos", "osx"].contains(os),
              let url = enclosure["url"].flatMap(URL.init(string:)), ApplicationUpdateURL.valid(url), enclosure["sparkle:deltaFrom"] == nil else { return }
        let display = fields["shortVersionString"] ?? enclosure["sparkle:shortVersionString"] ?? version
        func optional(_ field: String) -> String? { fields[field].flatMap { $0.isEmpty ? nil : $0 } }
        releases.append(.init(version: version, displayVersion: display, channel: optional("channel"), minimumOS: optional("minimumSystemVersion"), maximumOS: optional("maximumSystemVersion"), hardware: optional("hardwareRequirements"), storeID: nil))
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { invalid = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { invalid = true; parser.abortParsing() }
}
