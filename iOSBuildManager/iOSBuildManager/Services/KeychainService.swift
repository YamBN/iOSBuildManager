import Foundation
import Security

/// Minimal Keychain wrapper for the GitHub access token.
///
/// The token is a credential, so it never goes into `settings.json` alongside
/// the ordinary preferences — it lives in the login keychain where the OS
/// controls access to it.
enum KeychainService {
    static let service = "com.yambn.iOSBuildManager.github"
    static let account = "access-token"

    /// Stores (or replaces) the token. Returns false if the keychain refused.
    @discardableResult
    static func save(token: String, service: String = service, account: String = account) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // Available without unlocking beyond first login, and never synced to
        // other devices — this token is tied to this Mac's tooling.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func loadToken(service: String = service, account: String = account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    @discardableResult
    static func deleteToken(service: String = service, account: String = account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
