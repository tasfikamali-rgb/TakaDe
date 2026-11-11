import Foundation

/// The person using this device. Not an account on any server: in release 1 the profile,
/// and any linked sign-in, never leave the phone.
public struct LocalProfile: Hashable, Codable, Sendable {
    public let id: UUID
    /// Stored exactly as typed: never translated, transliterated or normalized.
    public var displayName: String
    /// "bn" or "en"; nil follows the phone.
    public var languageCode: String?
    /// "bengali", "latin" or nil for automatic.
    public var digitStyle: String?
    /// The Apple or Google sign-in linked on this device, if any.
    public var account: LinkedAccount?
    public let createdAt: Date

    public init(id: UUID = UUID(), displayName: String, languageCode: String? = nil, digitStyle: String? = nil,
                account: LinkedAccount? = nil, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
        self.digitStyle = digitStyle
        self.account = account
        self.createdAt = createdAt
    }
}

public enum SignInProvider: String, Codable, Sendable, CaseIterable {
    case apple, google
}

/// What TakaDe keeps from a sign-in. Tokens are never part of this: they live in the Keychain.
public struct LinkedAccount: Hashable, Codable, Sendable {
    public var provider: SignInProvider
    /// The provider's stable id for this person (Apple `user`, Google `sub`).
    public var providerUserID: String
    /// Optional. May be an Apple private relay address.
    public var email: String?

    public init(provider: SignInProvider, providerUserID: String, email: String?) {
        self.provider = provider
        self.providerUserID = providerUserID
        self.email = email
    }
}
