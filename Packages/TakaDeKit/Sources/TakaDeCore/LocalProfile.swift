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
    /// The Apple or Google sign-in linked on this device only, when no TakaDe account
    /// service is set up (ADR 0011).
    public var account: LinkedAccount?
    /// The TakaDe account's id on the sign-in service (ADR 0016), when signed in to one.
    /// The service holds only the account; groups and expenses stay on this phone.
    public var accountID: String?
    /// The account's email, as the sign-in service has it.
    public var accountEmail: String?
    public let createdAt: Date

    public init(id: UUID = UUID(), displayName: String, languageCode: String? = nil, digitStyle: String? = nil,
                account: LinkedAccount? = nil, accountID: String? = nil, accountEmail: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
        self.digitStyle = digitStyle
        self.account = account
        self.accountID = accountID
        self.accountEmail = accountEmail
        self.createdAt = createdAt
    }

    public var isSignedIn: Bool { accountID != nil || account != nil }
}

public enum SignInProvider: String, Codable, Sendable, CaseIterable {
    case apple, google, microsoft, email
}

/// One way into a TakaDe account: an Apple, Google or Microsoft sign-in, or an email
/// address. Several can be linked to the same account. A copy is kept on the phone so the
/// Account tab works offline; the sign-in service is the source of truth.
public struct AccountIdentity: Hashable, Codable, Sendable, Identifiable {
    /// The sign-in service's id for this link, used to unlink it.
    public let id: String
    public var provider: SignInProvider
    /// The provider's stable id for the person (Apple `sub`, Google `sub`, Microsoft `oid`).
    public var providerUserID: String
    public var email: String?
    public var linkedAt: Date

    public init(id: String, provider: SignInProvider, providerUserID: String, email: String?, linkedAt: Date) {
        self.id = id
        self.provider = provider
        self.providerUserID = providerUserID
        self.email = email
        self.linkedAt = linkedAt
    }
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
