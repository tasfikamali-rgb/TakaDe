import CryptoKit
import Foundation
import Security
import TakaDeCore

/// Group keys and the sharing sign-in, kept apart from the account's Keychain items so
/// signing out of an account doesn't break shared groups. Items stay on this phone only
/// (`ThisDeviceOnly`): a new phone joins again with a fresh invite link.
enum SyncKeychain {
    private static let service = "app.takade.sync"

    static func key(for group: GroupID) -> SymmetricKey? {
        get("key.\(group)").flatMap { Data(base64URLEncoded: $0) }.map(SymmetricKey.init(data:))
    }

    static func setKey(_ key: SymmetricKey, for group: GroupID) {
        set(key.withUnsafeBytes { Data($0) }.base64URLEncoded, for: "key.\(group)")
    }

    static func removeKey(for group: GroupID) {
        delete("key.\(group)")
        delete("rejoin.\(group)")
    }

    /// This phone's secret for moving its membership to a new sharing sign-in. Saved only
    /// after the relay stored its hash.
    static func rejoinSecret(for group: GroupID) -> String? { get("rejoin.\(group)") }

    static func setRejoinSecret(_ secret: String, for group: GroupID) { set(secret, for: "rejoin.\(group)") }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// For "Delete all my data": every group key and the sharing sign-in.
    static func deleteAll() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }
}
