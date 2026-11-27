import Foundation

public enum AppNetworkAction: String, Codable, CaseIterable, Sendable { case allow, deny }
public struct AppNetworkIdentity: Codable, Hashable, Sendable {
    public let identifier: String
    public let teamIdentifier: String?
    public let codeHash: String?
    public init(identifier: String, teamIdentifier: String?, codeHash: String? = nil) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.codeHash = teamIdentifier?.isEmpty == false ? nil : codeHash
    }
}
public struct AppNetworkRule: Codable, Equatable, Identifiable, Sendable {
    public var id: AppNetworkIdentity { identity }
    public let identity: AppNetworkIdentity
    public let name: String
    public var action: AppNetworkAction
    public var enabled: Bool
    public init(identity: AppNetworkIdentity, name: String, action: AppNetworkAction = .deny, enabled: Bool = true) {
        self.identity = identity
        self.name = name
        self.action = action
        self.enabled = enabled
    }
}
public struct AppNetworkPolicy: Codable, Equatable, Sendable {
    public var rules: [AppNetworkRule]
    public init(rules: [AppNetworkRule] = []) { self.rules = rules }
    /// Unknown applications and missing attribution pass. A rule never matches solely by a display name or
    /// PID.
    public func action(for identity: AppNetworkIdentity?) -> AppNetworkAction {
        guard let identity else { return .allow }
        let matches = rules.filter { rule in
            guard rule.enabled, rule.identity.identifier == identity.identifier else { return false }
            if let team = rule.identity.teamIdentifier { return !team.isEmpty && team == identity.teamIdentifier }
            guard let hash = rule.identity.codeHash, !hash.isEmpty else { return false }
            return hash == identity.codeHash
        }
        return matches.contains(where: { $0.action == .deny }) ? .deny : .allow
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 262_144 else { throw PolicyError.invalid }
        let policy = try JSONDecoder().decode(Self.self, from: data)
        guard policy.rules.count <= 512, policy.rules.allSatisfy({ rule in
            !rule.identity.identifier.isEmpty && rule.identity.identifier.utf8.count <= 512 && rule.name.utf8.count <= 1024 &&
            (rule.identity.teamIdentifier?.isEmpty == false || rule.identity.codeHash?.isEmpty == false)
        }) else { throw PolicyError.invalid }
        guard Set(policy.rules.map(\.id)).count == policy.rules.count else { throw PolicyError.invalid }
        return policy
    }
    public enum PolicyError: Error { case invalid }
}
