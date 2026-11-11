import Foundation

/// A signed-in session on the sign-in service. Kept only in the Keychain.
struct AuthSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: AuthUser

    var isExpiring: Bool { expiresAt.timeIntervalSinceNow < 60 }

    private static let keychainKey = "supabase.session"

    static func load() -> AuthSession? {
        guard let text = KeychainStore.get(keychainKey), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return }
        KeychainStore.set(text, for: Self.keychainKey)
    }

    static func clear() { KeychainStore.delete(keychainKey) }
}

/// The parts of the service's user record TakaDe reads.
struct AuthUser: Codable, Sendable {
    struct Identity: Codable, Sendable {
        /// The link's own id, used to unlink it.
        let identityID: String?
        /// The provider's id for the person.
        let id: String
        let provider: String
        let email: String?
        let createdAt: Date?
    }

    let id: String
    let email: String?
    let name: String?
    let createdAt: Date?
    let lastSignInAt: Date?
    let identities: [Identity]

    /// True when this sign-in just made the account, so "Sign in" can say no account was
    /// found and ask for a name.
    var isNew: Bool {
        guard let createdAt else { return false }
        return abs((lastSignInAt ?? Date()).timeIntervalSince(createdAt)) < 60
    }
}
