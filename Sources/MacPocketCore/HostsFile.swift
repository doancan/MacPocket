import Foundation

/// One address line of `/etc/hosts`. A line commented out with `#` that still parses as an entry is a disabled entry.
public struct HostsEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var address: String
    public var hostnames: [String]
    public var comment: String?
    public var isEnabled: Bool
    /// The line exactly as read; written back unchanged until the entry is edited, so untouched lines keep their layout.
    var original: String?

    public init(id: UUID = UUID(), address: String, hostnames: [String], comment: String? = nil, isEnabled: Bool = true) {
        self.id = id; self.address = address; self.hostnames = hostnames; self.comment = comment; self.isEnabled = isEnabled
    }

    /// macOS needs these to boot and resolve itself; they can't be disabled or removed here.
    public var isSystem: Bool {
        hostnames.contains { ["localhost", "broadcasthost"].contains($0.lowercased()) }
    }

    /// 0.0.0.0 (or ::) is the unroutable address hosts-based blockers use; loopback lines are local development sites.
    public var isBlock: Bool { !isSystem && ["0.0.0.0", "::"].contains(address) }

    var line: String {
        if let original { return original }
        var text = (isEnabled ? "" : "# ") + address + "\t" + hostnames.joined(separator: " ")
        if let comment, !comment.isEmpty { text += " # " + comment }
        return text
    }
}

public enum HostsLine: Equatable, Sendable {
    case entry(HostsEntry)
    /// `## Name - Start ##` … `## Name - End ##`, the block style local development tools write.
    case groupStart(String, original: String)
    case groupEnd(String, original: String)
    case other(String)
}

public struct HostsGroup: Identifiable, Equatable, Sendable {
    /// nil for entries outside any block.
    public let name: String?
    public let entries: [HostsEntry]
    public var id: String { name ?? "" }
    public var editable: [HostsEntry] { entries.filter { !$0.isSystem } }
    public var allEnabled: Bool { editable.allSatisfy(\.isEnabled) }
    public var anyEnabled: Bool { editable.contains(where: \.isEnabled) }
}

public enum HostsValidationError: Error, LocalizedError, Equatable, Sendable {
    case invalidAddress(String)
    case invalidHostname(String)
    case missingHostname
    case invalidGroupName

    public var errorDescription: String? {
        switch self {
        case let .invalidAddress(value): String(localized: "“\(value)” geçerli bir IPv4 ya da IPv6 adresi değil.")
        case let .invalidHostname(value): String(localized: "“\(value)” geçerli bir alan adı değil.")
        case .missingHostname: String(localized: "En az bir alan adı yaz.")
        case .invalidGroupName: String(localized: "Grup adı harf, rakam, boşluk ve - _ . karakterlerinden oluşabilir.")
        }
    }
}

public struct HostsFile: Equatable, Sendable {
    public static let path = "/etc/hosts"
    public var lines: [HostsLine]

    public init(parsing text: String) {
        var lines: [HostsLine] = []
        var raw = text.components(separatedBy: "\n")
        if raw.last == "" { raw.removeLast() }
        for line in raw {
            if let name = Self.marker(line, kind: "Start") {
                lines.append(.groupStart(name, original: line))
            } else if let name = Self.marker(line, kind: "End") {
                lines.append(.groupEnd(name, original: line))
            } else if var entry = Self.entry(line) {
                entry.original = line
                lines.append(.entry(entry))
            } else {
                lines.append(.other(line))
            }
        }
        self.lines = lines
    }

    public var text: String {
        lines.map { line in
            switch line {
            case let .entry(entry): entry.line
            case let .groupStart(_, original), let .groupEnd(_, original): original
            case let .other(text): text
            }
        }.joined(separator: "\n") + "\n"
    }

    public var entries: [HostsEntry] {
        lines.compactMap { if case let .entry(entry) = $0 { entry } else { nil } }
    }

    /// Entries outside any block first, then each block in file order.
    public var groups: [HostsGroup] {
        var order: [String?] = [nil]
        var members: [String: [HostsEntry]] = [:]
        var current: String?
        for line in lines {
            switch line {
            case let .groupStart(name, _):
                current = name
                if !order.contains(name) { order.append(name) }
            case .groupEnd: current = nil
            case let .entry(entry): members[current ?? "", default: []].append(entry)
            case .other: break
            }
        }
        return order.map { HostsGroup(name: $0, entries: members[$0 ?? ""] ?? []) }
            .filter { $0.name != nil || !$0.entries.isEmpty }
    }

    public mutating func setEnabled(_ id: UUID, _ enabled: Bool) {
        modify(id) { if !$0.isSystem { $0.isEnabled = enabled } }
    }

    public mutating func setGroupEnabled(_ name: String?, _ enabled: Bool) {
        for entry in groups.first(where: { $0.name == name })?.editable ?? [] { setEnabled(entry.id, enabled) }
    }

    public mutating func remove(_ id: UUID) {
        lines.removeAll { if case let .entry(entry) = $0 { entry.id == id && !entry.isSystem } else { false } }
    }

    /// Validates and appends at the end of `group` (created at the end of the file if new), or of the ungrouped part.
    @discardableResult
    public mutating func add(address: String, hostnames: String, comment: String = "", group: String? = nil) throws -> HostsEntry {
        let address = address.trimmingCharacters(in: .whitespaces)
        guard Self.isValidAddress(address) else { throw HostsValidationError.invalidAddress(address) }
        let names = hostnames.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }).map(String.init)
        guard !names.isEmpty else { throw HostsValidationError.missingHostname }
        if let bad = names.first(where: { !Self.isValidHostname($0) }) { throw HostsValidationError.invalidHostname(bad) }
        let note = comment.replacingOccurrences(of: "#", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let entry = HostsEntry(address: address, hostnames: names, comment: note.isEmpty ? nil : note)
        let group = group?.trimmingCharacters(in: .whitespaces)
        if let group, !group.isEmpty {
            guard group.range(of: #"^[\p{L}\p{N} ._-]{1,40}$"#, options: .regularExpression) != nil
            else { throw HostsValidationError.invalidGroupName }
            if let end = lines.firstIndex(where: { if case let .groupEnd(name, _) = $0 { name == group } else { false } }) {
                lines.insert(.entry(entry), at: end)
            } else {
                if let last = lines.last, last != .other("") { lines.append(.other("")) }
                lines.append(.groupStart(group, original: "## \(group) - Start ##"))
                lines.append(.entry(entry))
                lines.append(.groupEnd(group, original: "## \(group) - End ##"))
            }
        } else {
            let firstGroup = lines.firstIndex { if case .groupStart = $0 { true } else { false } } ?? lines.endIndex
            let lastEntry = lines[..<firstGroup].lastIndex { if case .entry = $0 { true } else { false } }
            lines.insert(.entry(entry), at: lastEntry.map { $0 + 1 } ?? firstGroup)
        }
        return entry
    }

    private mutating func modify(_ id: UUID, _ change: (inout HostsEntry) -> Void) {
        guard let index = lines.firstIndex(where: { if case let .entry(entry) = $0 { entry.id == id } else { false } }),
              case var .entry(entry) = lines[index] else { return }
        let before = entry
        change(&entry)
        if entry != before { entry.original = nil }
        lines[index] = .entry(entry)
    }

    // MARK: Parsing

    static func marker(_ line: String, kind: String) -> String? {
        let pattern = #"^\s*##\s*(.+?)\s*-\s*"# + kind + #"\s*##\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    static func entry(_ line: String) -> HostsEntry? {
        var body = Substring(line).drop { $0 == " " || $0 == "\t" }
        var enabled = true
        if body.hasPrefix("#") {
            // "##" lines are headings, never disabled entries.
            guard !body.hasPrefix("##") else { return nil }
            enabled = false
            body = body.dropFirst().drop { $0 == " " || $0 == "\t" }
        }
        var comment: String?
        if let hash = body.firstIndex(of: "#") {
            let note = body[body.index(after: hash)...].trimmingCharacters(in: .whitespaces)
            comment = note.isEmpty ? nil : note
            body = body[..<hash]
        }
        let fields = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count >= 2, isValidAddress(fields[0]), fields.dropFirst().allSatisfy(isValidHostname) else { return nil }
        return HostsEntry(address: fields[0], hostnames: Array(fields.dropFirst()), comment: comment, isEnabled: enabled)
    }

    public static func isValidAddress(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        // IPv6 zone ids (fe80::1%lo0) are allowed in hosts.
        let bare = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, bare, &v6) == 1
    }

    public static func isValidHostname(_ text: String) -> Bool {
        text.count <= 253 && text.range(
            of: #"^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\.?$"#,
            options: .regularExpression) != nil
    }
}

public enum HostsWriteError: Error, LocalizedError, Equatable, Sendable {
    case cancelled
    case failed(code: Int, message: String)
    case noBackup

    public var errorDescription: String? {
        switch self {
        case .cancelled: String(localized: "Yönetici onayı iptal edildi; hosts dosyası değişmedi.")
        case let .failed(code, message): String(localized: "Hosts dosyası yazılamadı (\(code)): \(message)")
        case .noBackup: String(localized: "Henüz MacPocket yedeği yok.")
        }
    }
}

public enum HostsWriter {
    public static let backupPath = "/etc/hosts.macpocket-backup"

    /// The shell command run as root. `cat >` keeps the file's owner and mode; the previous file is backed up first
    /// and the DNS cache flushed so the change applies at once. `source` is a path MacPocket created.
    public static func command(source: String) throws -> String {
        guard source.range(of: #"^/[A-Za-z0-9/._-]+$"#, options: .regularExpression) != nil
        else { throw HostsWriteError.failed(code: -1, message: source) }
        return "/bin/cp -p /etc/hosts \(backupPath) && /bin/cat \(source) > /etc/hosts"
            + " && /usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"
    }

    /// Writes `text` to `/etc/hosts` after the system administrator prompt.
    public static func write(_ text: String) async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("macpocket-hosts-\(UUID().uuidString).txt")
        try text.write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }
        try await run(try command(source: source.path))
    }

    public static var backupText: String? { try? String(contentsOfFile: backupPath, encoding: .utf8) }

    private static func run(_ command: String) async throws {
        do {
            _ = try await AdministratorShell.run(command)
        } catch AdministratorShell.Failure.cancelled {
            throw HostsWriteError.cancelled
        } catch let AdministratorShell.Failure.failed(code, message) {
            throw HostsWriteError.failed(code: code, message: message)
        }
    }
}
