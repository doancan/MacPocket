import Foundation
import MacPocketCore
import Security
import LocalAuthentication

@MainActor protocol WeatherCredentialStoring {
    func contains(_ source: WeatherSource) -> Bool
    func read(_ source: WeatherSource) throws -> String?
    func save(_ value: String?, for source: WeatherSource) throws
}

@MainActor struct WeatherKeychainStore: WeatherCredentialStoring {
    var namespace = "com.doancan.MacPocket.weather"
    private func query(_ source: WeatherSource) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: namespace,
         kSecAttrAccount as String: source.rawValue,
         kSecUseAuthenticationContext as String: context]
    }
    func contains(_ source: WeatherSource) -> Bool {
        var query = query(source)
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    func read(_ source: WeatherSource) throws -> String? {
        var query = query(source)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { throw WeatherCredentialError.unavailable }
        return value
    }
    func save(_ value: String?, for source: WeatherSource) throws {
        let query = query(source)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw WeatherCredentialError.unavailable }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecUseAuthenticationContext as String] = nil
            addition.merge(attributes) { _, new in new }
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw WeatherCredentialError.unavailable }
        } else if status != errSecSuccess { throw WeatherCredentialError.unavailable }
    }
}

enum WeatherCredentialError: LocalizedError {
    case unavailable
    var errorDescription: String? { String(localized: "API anahtarına Anahtar Zinciri üzerinden erişilemedi. Anahtar Zinciri’nin kilidini ve uygulama erişimini kontrol et.") }
}
