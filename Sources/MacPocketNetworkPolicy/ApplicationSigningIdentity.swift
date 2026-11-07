import Darwin
import Foundation
import Security

public enum ApplicationSigningIdentity {
    public static func read(at url: URL) -> AppNetworkIdentity? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        return identity(code)
    }
    public static func read(auditToken: Data?) -> AppNetworkIdentity? {
        guard let auditToken, auditToken.count == MemoryLayout<audit_token_t>.size else { return nil }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: auditToken] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return identity(staticCode)
    }
    private static func identity(_ code: SecStaticCode) -> AppNetworkIdentity? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String:Any], let identifier = values[kSecCodeInfoIdentifier as String] as? String else { return nil }
        let hash = (values[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
        let team = values[kSecCodeInfoTeamIdentifier as String] as? String
        guard team?.isEmpty == false || hash?.isEmpty == false else { return nil }
        return .init(identifier: identifier, teamIdentifier: team, codeHash: hash)
    }
}
