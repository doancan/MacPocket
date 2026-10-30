import Foundation

// MARK: - Power source scopes

/// The power source column of `pmset -g custom` and the matching `pmset` scope flag.
public enum PMPowerProfile: String, CaseIterable, Codable, Sendable, Identifiable {
    case battery, ac, ups

    public var id: String { rawValue }

    /// Header line printed by `pmset -g custom`.
    public var header: String {
        switch self {
        case .battery: "Battery Power"
        case .ac: "AC Power"
        case .ups: "UPS Power"
        }
    }

    public var title: String {
        switch self {
        case .battery: String(localized: "Pil")
        case .ac: String(localized: "Güç adaptörü")
        case .ups: "UPS"
        }
    }

    public var scope: PMSetScope {
        switch self {
        case .battery: .battery
        case .ac: .charger
        case .ups: .ups
        }
    }

    init?(header: String) {
        guard let match = Self.allCases.first(where: { $0.header == header }) else { return nil }
        self = match
    }
}

/// `pmset` scope flags. Only these four are ever emitted.
public enum PMSetScope: String, CaseIterable, Codable, Sendable {
    case all = "-a", battery = "-b", charger = "-c", ups = "-u"
}

// MARK: - Setting catalog

/// How a pmset value is presented and validated.
public enum PMValueKind: Equatable, Sendable {
    case minutes(ClosedRange<Int>)
    case seconds(ClosedRange<Int>)
    case percent
    case toggle
    case choice([PMChoice])
    case raw
}

public struct PMChoice: Equatable, Hashable, Sendable {
    public let value: Int
    public let title: String
    public init(_ value: Int, _ title: String) { self.value = value; self.title = title }
}

/// Every pmset key MacPocket recognises. Keys not listed here are shown read-only with their raw name.
/// Raw values are the exact pmset tokens; they are the only setting names ever placed in a command.
public enum PMSettingKey: String, CaseIterable, Codable, Sendable {
    case displaysleep, sleep, disksleep
    case womp, powernap, autorestart, lidwake, acwake, proximitywake, halfdim
    case lowpowermode, powermode, ttyskeepawake, tcpkeepalive, networkoversleep
    case hibernatemode, standby, standbydelay, standbydelaylow, standbydelayhigh, highstandbythreshold
    case autopoweroff, autopoweroffdelay, gpuswitch, darkwakes, disablesleep = "SleepDisabled"
    case destroyfvkeyonstandby, autorestartatconnect, sleepOnPowerButton = "Sleep On Power Button"
    case hibernatefile, lessbright, ring, sms, haltlevel, haltafter, haltremain

    public var title: String {
        switch self {
        case .displaysleep: String(localized: "Ekranı kapat")
        case .sleep: String(localized: "Sistem uykusu")
        case .disksleep: String(localized: "Diskleri uyut")
        case .womp: String(localized: "Ağ erişimiyle uyandır")
        case .powernap: String(localized: "Power Nap")
        case .autorestart: String(localized: "Elektrik kesintisinden sonra başlat")
        case .lidwake: String(localized: "Kapak açılınca uyan")
        case .acwake: String(localized: "Adaptör takılınca uyan")
        case .proximitywake: String(localized: "Yakındaki aygıtlarla uyan")
        case .halfdim: String(localized: "Kapatmadan önce ekranı karart")
        case .lowpowermode: String(localized: "Düşük Güç Modu")
        case .powermode: String(localized: "Enerji modu")
        case .ttyskeepawake: String(localized: "Uzak oturumlar uyanık tutar")
        case .tcpkeepalive: String(localized: "Uykuda ağ bağlantısını koru")
        case .networkoversleep: String(localized: "Uykuda ağ hizmetleri")
        case .hibernatemode: String(localized: "Hazırda bekletme modu")
        case .standby: String(localized: "Bekleme (standby)")
        case .standbydelay: String(localized: "Bekleme gecikmesi")
        case .standbydelaylow: String(localized: "Bekleme gecikmesi (düşük pil)")
        case .standbydelayhigh: String(localized: "Bekleme gecikmesi (yüksek pil)")
        case .highstandbythreshold: String(localized: "Yüksek pil eşiği")
        case .autopoweroff: String(localized: "Otomatik kapanma")
        case .autopoweroffdelay: String(localized: "Otomatik kapanma gecikmesi")
        case .gpuswitch: String(localized: "Grafik işlemci geçişi")
        case .darkwakes: String(localized: "Arka planda uyanmalar")
        case .disablesleep: String(localized: "Uyku tamamen kapalı")
        case .destroyfvkeyonstandby: String(localized: "Beklemede FileVault anahtarını sil")
        case .autorestartatconnect: String(localized: "Bağlanınca otomatik başlat")
        case .sleepOnPowerButton: String(localized: "Güç düğmesiyle uyu")
        case .hibernatefile: String(localized: "Uyku görüntüsü dosyası")
        case .lessbright: String(localized: "Pilde ekranı hafif karart")
        case .ring: String(localized: "Modem çağrısıyla uyan")
        case .sms: String(localized: "Ani hareket sensörü")
        case .haltlevel: String(localized: "UPS kapanma seviyesi")
        case .haltafter: String(localized: "UPS kapanma süresi")
        case .haltremain: String(localized: "UPS kalan süre eşiği")
        }
    }

    public var explanation: String {
        switch self {
        case .displaysleep: String(localized: "Bu kadar dakika işlem yapılmazsa ekran kapanır. 0: hiçbir zaman.")
        case .sleep: String(localized: "Bu kadar dakika işlem yapılmazsa sistem uyur. 0: hiçbir zaman.")
        case .disksleep: String(localized: "Döner diskler bu süre sonunda durdurulur. 0: hiçbir zaman.")
        case .womp: String(localized: "Ağdan gelen erişim isteği (Wake on LAN) Mac’i uyandırabilir.")
        case .powernap: String(localized: "Uykudayken Mail, iCloud ve yedekleme gibi işler zaman zaman güncellenir.")
        case .autorestart: String(localized: "Elektrik kesilip geri geldiğinde Mac kendiliğinden açılır.")
        case .lidwake: String(localized: "Dizüstü kapağı açıldığında Mac uyanır.")
        case .acwake: String(localized: "Güç adaptörü takılıp çıkarıldığında Mac uyanır.")
        case .proximitywake: String(localized: "Aynı iCloud hesabındaki yakın aygıtlar Mac’i uyandırabilir.")
        case .halfdim: String(localized: "Ekran kapanmadan önce yarı parlaklığa iner.")
        case .lowpowermode: String(localized: "Enerji tüketimini azaltır; performans ve arka plan işleri kısılır.")
        case .powermode: String(localized: "Otomatik, düşük güç veya yüksek güç modu (destekleyen Mac’lerde).")
        case .ttyskeepawake: String(localized: "Etkin SSH/terminal oturumları varken sistem uyumaz.")
        case .tcpkeepalive: String(localized: "Uykudayken ağ bağlantıları canlı tutulur; Find My ve paylaşım hizmetleri çalışır.")
        case .networkoversleep: String(localized: "Paylaşılan ağ hizmetlerinin uykuda nasıl sunulacağı. Apple değiştirilmesini desteklemez.")
        case .hibernatemode: String(localized: "Uykuda belleğin diske yazılma biçimi. Masaüstünde 0, dizüstünde 3 varsayılandır.")
        case .standby: String(localized: "Uzun uykudan sonra bellek diske yazılır ve daha az enerji harcanır.")
        case .standbydelay: String(localized: "Bekleme moduna geçmeden önce uykuda geçen saniye.")
        case .standbydelaylow: String(localized: "Pil eşiğin altındayken beklemeye geçiş süresi (saniye).")
        case .standbydelayhigh: String(localized: "Pil eşiğin üstündeyken beklemeye geçiş süresi (saniye).")
        case .highstandbythreshold: String(localized: "Düşük ve yüksek bekleme gecikmeleri arasındaki pil yüzdesi.")
        case .autopoweroff: String(localized: "Uzun uykudan sonra Mac tamamen kapalı duruma geçer (Intel).")
        case .autopoweroffdelay: String(localized: "Otomatik kapanmaya geçmeden önce uykuda geçen saniye.")
        case .gpuswitch: String(localized: "Çift grafik işlemcili Mac’lerde hangi GPU’nun kullanılacağı.")
        case .darkwakes: String(localized: "Power Nap sırasında ekran kapalıyken yapılan kısa uyanmalar.")
        case .disablesleep: String(localized: "Sistem uykusu tamamen engellenmiş. Yalnızca görüntülenir.")
        case .destroyfvkeyonstandby: String(localized: "Beklemeye geçerken FileVault anahtarı bellekten silinir; uyanınca parola gerekir.")
        case .autorestartatconnect: String(localized: "Güç bağlandığında Mac otomatik başlar. Yalnızca görüntülenir.")
        case .sleepOnPowerButton: String(localized: "Güç düğmesine kısa basış Mac’i uyutur. Yalnızca görüntülenir.")
        case .hibernatefile: String(localized: "Hazırda bekletme görüntüsünün diskteki konumu.")
        case .lessbright: String(localized: "Pile geçince ekran parlaklığı biraz düşürülür.")
        case .ring: String(localized: "Eski modem donanımı için. Modern Mac’lerde etkisizdir.")
        case .sms: String(localized: "Eski dizüstülerde düşme algılayıcısı.")
        case .haltlevel: String(localized: "UPS şarjı bu yüzdeye inince Mac kapanır.")
        case .haltafter: String(localized: "UPS’e geçtikten bu kadar dakika sonra Mac kapanır.")
        case .haltremain: String(localized: "UPS’in kalan süresi bu dakikanın altına inince Mac kapanır.")
        }
    }

    public var kind: PMValueKind {
        switch self {
        case .displaysleep, .sleep, .disksleep: .minutes(0...1440)
        case .standbydelay, .standbydelaylow, .standbydelayhigh, .autopoweroffdelay: .seconds(0...604_800)
        case .highstandbythreshold, .haltlevel: .percent
        case .haltafter, .haltremain: .minutes(0...1440)
        case .hibernatemode: .choice([PMChoice(0, String(localized: "Yalnızca bellek (0)")), PMChoice(3, String(localized: "Bellek + disk (3)")),
                                      PMChoice(25, String(localized: "Yalnızca disk (25)"))])
        case .gpuswitch: .choice([PMChoice(0, String(localized: "Tümleşik GPU")), PMChoice(1, String(localized: "Ayrık GPU")), PMChoice(2, String(localized: "Otomatik"))])
        case .powermode: .choice([PMChoice(0, String(localized: "Otomatik")), PMChoice(1, String(localized: "Düşük güç")), PMChoice(2, String(localized: "Yüksek güç"))])
        case .lowpowermode: .choice([PMChoice(0, String(localized: "Kapalı")), PMChoice(1, String(localized: "Açık"))])
        case .hibernatefile: .raw
        default: .toggle
        }
    }

    /// Keys a user may change. Read-only keys are unsupported by Apple, security sensitive, or obsolete.
    public var isEditable: Bool {
        switch self {
        case .displaysleep, .sleep, .disksleep, .womp, .powernap, .autorestart, .lidwake, .acwake,
             .proximitywake, .halfdim, .lowpowermode, .powermode, .ttyskeepawake, .tcpkeepalive,
             .hibernatemode, .standby, .standbydelay, .standbydelaylow, .standbydelayhigh,
             .highstandbythreshold, .autopoweroff, .autopoweroffdelay, .gpuswitch, .lessbright,
             .haltlevel, .haltafter, .haltremain:
            true
        default:
            false
        }
    }

    /// macOS already offers a control for this in System Settings (Battery, Energy, Lock Screen), so MacPocket
    /// doesn't duplicate it; only Terminal-only settings are listed.
    public var hasSystemSettingsControl: Bool {
        switch self {
        case .displaysleep, .sleep, .disksleep, .womp, .powernap, .autorestart, .lowpowermode, .powermode,
             .lessbright, .gpuswitch:
            true
        default:
            false
        }
    }

    /// Display order: the settings people change most come first.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? Int.max }

    /// Accepts values pmset itself accepts, constrained to the documented ranges.
    public func accepts(_ value: Int) -> Bool {
        switch kind {
        case let .minutes(range), let .seconds(range): range.contains(value)
        case .percent: (0...100).contains(value)
        case .toggle: value == 0 || value == 1
        case let .choice(choices): choices.contains { $0.value == value }
        case .raw: false
        }
    }

    /// Human value, e.g. "10 dk", "Açık", "Hiçbir zaman".
    public func display(_ value: Int) -> String {
        switch kind {
        case .minutes:
            return value == 0 ? String(localized: "Hiçbir zaman") : String(localized: "\(value) dk")
        case .seconds:
            if value >= 3600, value % 3600 == 0 { return String(localized: "\(value / 3600) sa") }
            if value >= 60, value % 60 == 0 { return String(localized: "\(value / 60) dk") }
            return String(localized: "\(value) sn")
        case .percent:
            return String(localized: "%\(value)")
        case .toggle:
            return value == 0 ? String(localized: "Kapalı") : (value == 1 ? String(localized: "Açık") : "\(value)")
        case let .choice(choices):
            return choices.first { $0.value == value }?.title ?? "\(value)"
        case .raw:
            return "\(value)"
        }
    }
}

// MARK: - Parsed values

public struct PMSettingValue: Equatable, Sendable, Identifiable {
    public var id: String { name }
    /// The raw token as pmset prints it.
    public let name: String
    public let key: PMSettingKey?
    public let number: Int?
    /// Raw value text (for non-numeric values such as `hibernatefile`).
    public let rawValue: String
    /// Trailing annotation, e.g. "(sleep prevented by powerd, caffeinate)".
    public let note: String?

    public init(name: String, number: Int?, rawValue: String, note: String?) {
        self.name = name
        self.key = PMSettingKey(rawValue: name)
        self.number = number
        self.rawValue = rawValue
        self.note = note
    }

    public var title: String { key?.title ?? name }
    public var displayValue: String {
        if let key, let number { return key.display(number) }
        return rawValue
    }
}

public struct PMSettingsProfile: Equatable, Sendable, Identifiable {
    public var id: PMPowerProfile { profile }
    public let profile: PMPowerProfile
    public let values: [PMSettingValue]

    public func value(_ key: PMSettingKey) -> PMSettingValue? { values.first { $0.key == key } }

    /// Settings that have no control in System Settings; unknown keys stay visible so nothing pmset reports is hidden.
    public var terminalOnlyValues: [PMSettingValue] { values.filter { !($0.key?.hasSystemSettingsControl ?? false) } }
}

/// `pmset -g` "Currently in use" block plus processes reported as preventing sleep.
public struct PMLiveSettings: Equatable, Sendable {
    public let values: [PMSettingValue]
    public var sleepPreventedBy: [String] {
        for value in values {
            guard let note = value.note, let range = note.range(of: "prevented by ") else { continue }
            let list = note[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }
    public func value(_ key: PMSettingKey) -> PMSettingValue? { values.first { $0.key == key } }
}

public enum PMSettingsParser {
    /// Parses `pmset -g custom`. Unknown section headers are ignored.
    public static func parseCustom(_ text: String) -> [PMSettingsProfile] {
        var result: [PMSettingsProfile] = []
        var current: PMPowerProfile?
        var values: [PMSettingValue] = []
        func flush() {
            if let current, !values.isEmpty { result.append(PMSettingsProfile(profile: current, values: sorted(values))) }
            values = []
        }
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if !line.hasPrefix(" "), trimmed.hasSuffix(":") {
                flush()
                current = PMPowerProfile(header: String(trimmed.dropLast()))
                continue
            }
            if current != nil, let value = parseLine(line) { values.append(value) }
        }
        flush()
        return result
    }

    /// Parses the "Currently in use:" block of plain `pmset -g`.
    public static func parseLive(_ text: String) -> PMLiveSettings {
        var values: [PMSettingValue] = []
        var inBlock = false
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Currently in use") { inBlock = true; continue }
            guard inBlock, !trimmed.isEmpty else { continue }
            if !line.hasPrefix(" ") { break }
            if let value = parseLine(line) { values.append(value) }
        }
        return PMLiveSettings(values: sorted(values))
    }

    /// One `  key   value [annotation]` row. Keys may contain spaces ("Sleep On Power Button 1").
    static func parseLine(_ line: String) -> PMSettingValue? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // The first purely numeric token after the key is the value; everything after it is a note.
        if let index = tokens.indices.dropFirst().first(where: { Int(tokens[$0]) != nil }) {
            let name = tokens[..<index].joined(separator: " ")
            let note = tokens[(index + 1)...].joined(separator: " ")
            return PMSettingValue(name: name, number: Int(tokens[index]), rawValue: tokens[index],
                                  note: note.isEmpty ? nil : note)
        }
        guard tokens.count >= 2 else { return nil }
        return PMSettingValue(name: tokens[0], number: nil, rawValue: tokens[1...].joined(separator: " "), note: nil)
    }

    private static func sorted(_ values: [PMSettingValue]) -> [PMSettingValue] {
        values.sorted { lhs, rhs in
            let left = lhs.key?.order ?? Int.max, right = rhs.key?.order ?? Int.max
            return left == right ? lhs.name < rhs.name : left < right
        }
    }
}

// MARK: - Privileged command builder

public enum PMSetCommandError: Error, LocalizedError, Equatable, Sendable {
    case notEditable(String)
    case valueOutOfRange(key: String, value: Int)
    case unknownKey(String)
    case malformed

    public var errorDescription: String? {
        switch self {
        case let .notEditable(key): String(localized: "“\(key)” ayarı MacPocket’ten değiştirilemez.")
        case let .valueOutOfRange(key, value): String(localized: "“\(key)” için \(value) geçerli bir değer değil.")
        case let .unknownKey(key): String(localized: "Bilinmeyen güç ayarı: \(key).")
        case .malformed: String(localized: "Komut güvenlik doğrulamasından geçmedi.")
        }
    }
}

/// One validated `pmset` change. The command is assembled only from the scope enum, the key enum's
/// raw value and a range-checked integer, so no caller-provided text can reach the shell.
public struct PMSetCommand: Equatable, Sendable {
    public static let executable = "/usr/bin/pmset"
    public let scope: PMSetScope
    public let key: PMSettingKey
    public let value: Int

    public init(scope: PMSetScope, key: PMSettingKey, value: Int) throws {
        guard key.isEditable else { throw PMSetCommandError.notEditable(key.rawValue) }
        guard key.accepts(value) else { throw PMSetCommandError.valueOutOfRange(key: key.rawValue, value: value) }
        self.scope = scope; self.key = key; self.value = value
    }

    /// Parses a raw key name; anything outside the catalog is rejected.
    public init(scope: PMSetScope, keyName: String, value: Int) throws {
        guard let key = PMSettingKey(rawValue: keyName) else { throw PMSetCommandError.unknownKey(keyName) }
        try self.init(scope: scope, key: key, value: value)
    }

    public var arguments: [String] { [scope.rawValue, key.rawValue, String(value)] }

    /// Exactly what the confirmation sheet shows and what runs.
    public var commandLine: String { ([Self.executable] + arguments).joined(separator: " ") }

    /// Defense in depth: the final string must match the strict grammar before it is executed.
    public func validatedCommandLine() throws -> String {
        let line = commandLine
        guard line.range(of: #"^/usr/bin/pmset -[abcu] [a-z]+ [0-9]{1,6}$"#, options: .regularExpression) != nil
        else { throw PMSetCommandError.malformed }
        return line
    }

    /// AppleScript source. `with administrator privileges` triggers the system authentication prompt.
    public func appleScriptSource() throws -> String {
        "do shell script \"\(try validatedCommandLine())\" with administrator privileges"
    }
}

/// Runs a validated pmset change with administrator rights.
public protocol PMSetPrivilegedRunning: Sendable {
    func run(_ command: PMSetCommand) async throws
}

public enum PMSetRunError: Error, LocalizedError, Equatable, Sendable {
    case cancelled
    case failed(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: String(localized: "Yönetici onayı iptal edildi; ayar değişmedi.")
        case let .failed(code, message): String(localized: "pmset başarısız oldu (\(code)): \(message)")
        }
    }
}

/// Uses NSAppleScript `do shell script … with administrator privileges`, which shows the standard
/// macOS authentication dialog. Executed on a private serial queue so the UI never blocks.
public struct AppleScriptPMSetRunner: PMSetPrivilegedRunning {
    private static let queue = DispatchQueue(label: "MacPocket.pmset.privileged", qos: .userInitiated)

    public init() {}

    public func run(_ command: PMSetCommand) async throws {
        let source = try command.appleScriptSource()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: PMSetCommandError.malformed); return
                }
                _ = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? String(localized: "Bilinmeyen hata")
                    continuation.resume(throwing: code == -128 ? PMSetRunError.cancelled
                                                               : PMSetRunError.failed(code: code, message: message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
