import Foundation
import UsageCore

public enum AIUsageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, grok
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self {
        case .claude: String(localized: "Claude")
        case .codex: String(localized: "Codex / ChatGPT")
        case .grok: String(localized: "Grok")
        }
    }
    public var shortName: String {
        switch self { case .claude: String(localized: "Cl"); case .codex: String(localized: "Cdx"); case .grok: String(localized: "Gr") }
    }
    public var providerID: ProviderID {
        switch self { case .claude: .claude; case .codex: .openai; case .grok: .xai }
    }
    public var symbol: String {
        switch self { case .claude: "sparkle"; case .codex: "terminal"; case .grok: "xmark" }
    }
    public var loginHelp: String {
        switch self {
        case .claude: String(localized: "Claude Code’da bu profile giriş yap, sonra yenile.")
        case .codex: String(localized: "Bu hesabın CODEX_HOME klasöründe codex login çalıştır, sonra auth.json dosyasını seç.")
        case .grok: String(localized: "Bu hesabın Grok CLI oturumunu aç, sonra auth.json dosyasını seç.")
        }
    }
}

public enum AIUsageSource: Codable, Equatable, Sendable {
    case claudeKeychain(service: String, account: String)
    case claudeProfile(directory: String, service: String?)
    case codexFile(path: String)
    case grokFile(path: String)

    public var provider: AIUsageProvider {
        switch self { case .claudeKeychain, .claudeProfile: .claude; case .codexFile: .codex; case .grokFile: .grok }
    }
    public var location: String {
        switch self {
        case .claudeKeychain(let service, _): service
        case .claudeProfile(let directory, _): directory
        case .codexFile(let path), .grokFile(let path): path
        }
    }
    public var identity: String {
        switch self {
        case .claudeKeychain(let service, let account): "claude-keychain:\(service):\(account)"
        case .claudeProfile(let directory, _): "claude-profile:\(URL(fileURLWithPath: directory).standardizedFileURL.path)"
        case .codexFile(let path): "codex:\(URL(fileURLWithPath: path).standardizedFileURL.path)"
        case .grokFile(let path): "grok:\(URL(fileURLWithPath: path).standardizedFileURL.path)"
        }
    }
    var cacheIdentity: String {
        if case .claudeProfile(_, let service) = self { return identity + "|" + (service ?? "") }
        return identity
    }
    public var isValid: Bool {
        switch self {
        case .claudeKeychain(let service, let account):
            service.hasPrefix("Claude Code-credentials") && !account.isEmpty && service.utf8.count < 1024
        case .claudeProfile(let directory, let service):
            Self.validPath(directory) && (service == nil || service!.hasPrefix("Claude Code-credentials"))
        case .codexFile(let path), .grokFile(let path): Self.validPath(path)
        }
    }
    private static func validPath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count < 4096 && !path.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}

public struct AIUsageAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var source: AIUsageSource
    public var enabled: Bool
    public var showInMenuBar: Bool
    public var provider: AIUsageProvider { source.provider }
    public init(id: UUID = UUID(), name: String, source: AIUsageSource, enabled: Bool = true, showInMenuBar: Bool = true) {
        self.id = id
        self.name = name
        self.source = source
        self.enabled = enabled
        self.showInMenuBar = showInMenuBar
    }
}

public enum AIUsageDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case remaining, used
    public var id: String { rawValue }
    public var localizedTitle: String {
        switch self { case .remaining: String(localized: "Kalan kota"); case .used: String(localized: "Kullanılan kota") }
    }
    public func percent(_ used: Double) -> Double {
        let safe = used.isFinite ? min(100, max(0, used)) : 0
        return self == .remaining ? 100 - safe : safe
    }
}

public struct AIUsageSettings: Codable, Equatable, Sendable {
    public static let key = "MacPocket.aiUsage.settings.v1"
    public var accounts: [AIUsageAccount] = []
    public var mode = AIUsageDisplayMode.remaining
    public var refreshMinutes = 5
    public var warning = 65.0
    public var critical = 85.0
    public var alertsEnabled = false
    public var floatingPanel = false
    public var floatingHorizontal = false
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case accounts, mode, refreshMinutes, warning, critical, alertsEnabled, floatingPanel, floatingHorizontal
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([AIUsageAccount].self, forKey: .accounts) ?? []
        mode = try c.decodeIfPresent(AIUsageDisplayMode.self, forKey: .mode) ?? .remaining
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5
        warning = try c.decodeIfPresent(Double.self, forKey: .warning) ?? 65
        critical = try c.decodeIfPresent(Double.self, forKey: .critical) ?? 85
        alertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? false
        floatingPanel = try c.decodeIfPresent(Bool.self, forKey: .floatingPanel) ?? false
        floatingHorizontal = try c.decodeIfPresent(Bool.self, forKey: .floatingHorizontal) ?? false
    }
    public var normalized: Self {
        var value = self
        var ids = Set<UUID>(), sources = Set<String>()
        value.accounts = Array(accounts.filter {
            $0.source.isValid && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ids.insert($0.id).inserted && sources.insert($0.source.identity).inserted
        }.prefix(32)).map { var a = $0; a.name = String(a.name.prefix(80)); return a }
        value.refreshMinutes = min(60, max(5, refreshMinutes))
        value.warning = warning.isFinite ? min(98, max(1, warning)) : 65
        value.critical = critical.isFinite ? min(100, max(value.warning + 1, critical)) : max(value.warning + 1, 85)
        return value
    }
    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key), data.count <= 256 * 1024,
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings.normalized
    }
    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(normalized), data != defaults.data(forKey: Self.key) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

public enum AIUsageText {
    public static func limitTitle(_ limit: UsageLimit) -> String {
        if limit.id == "session" { return String(localized: "Oturum") }
        if limit.id == "monthly" { return String(localized: "Aylık") }
        if limit.id == "weekly_all" { return String(localized: "Haftalık") }
        if limit.id.hasPrefix("weekly_scoped#") {
            let model = String(limit.id.dropFirst("weekly_scoped#".count))
            return String(localized: "Haftalık (\(model))")
        }
        if limit.id == "weekly_scoped" { return String(localized: "Modele özel haftalık") }
        return String(localized: "Diğer limit")
    }
    public static func status(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return String(localized: "Henüz güncellenmedi") }
        switch snapshot.status {
        case .ok: return snapshot.limits.isEmpty ? String(localized: "Bu hesap için kota verisi sunulmadı.") : String(localized: "Güncel")
        case .needsSignIn: return String(localized: "Giriş gerekli")
        case .keychainDenied: return String(localized: "Anahtar Zinciri erişimine izin verilmeli.")
        case .rateLimited: return String(localized: "İstek sınırı nedeniyle bekleniyor")
        case .stale(let reason):
            if reason.lowercased().contains("network") { return String(localized: "Bağlantı sorunu; son değerler gösteriliyor.") }
            return String(localized: "Oturumu ilgili CLI’da yenile; son değerler güncel olmayabilir.")
        case .error(let message):
            if message.hasPrefix("HTTP "), let code = Int(message.dropFirst(5)) { return String(localized: "Kota sorgusu başarısız (HTTP \(code)).") }
            return String(localized: "Kota verisi okunamadı. Oturumu ve bağlantıyı kontrol et.")
        }
    }
}
