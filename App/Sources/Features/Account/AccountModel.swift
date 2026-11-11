import AuthenticationServices
import Foundation
import Observation
import TakaDeCore

/// The device owner's profile and optional Apple or Google sign-in. Everything here stays on
/// the phone: there is no TakaDe server (docs/adr/0011-on-device-sign-in.md).
@MainActor
@Observable
final class AccountModel {
    /// Kept in UserDefaults too, because new groups read the name from there.
    static let nameKey = "myDisplayName"

    private(set) var profile: LocalProfile?
    private(set) var isLoaded = false
    let store: ProfileRepository
    let google: GoogleSignInService?

    init(store: ProfileRepository, google: GoogleOAuthConfig? = .current) {
        self.store = store
        self.google = google.map(GoogleSignInService.init(config:))
    }

    var needsOnboarding: Bool { isLoaded && profile == nil }
    var account: LinkedAccount? { profile?.account }

    func load() async {
        profile = try? await store.profile()
        isLoaded = true
        await checkAppleCredential()
    }

    // MARK: Sign-in

    /// Reads what Apple shared. Name and email arrive only on the first sign-in.
    func identity(from authorization: ASAuthorization) -> (account: LinkedAccount, name: String?)? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default, options: []) }
        return (LinkedAccount(provider: .apple, providerUserID: credential.user, email: credential.email),
                name?.trimmingCharacters(in: .whitespaces).isEmpty == false ? name : nil)
    }

    func signInWithGoogle() async throws -> (account: LinkedAccount, name: String?) {
        guard let google else { throw GoogleSignInService.Failure.couldNotStart }
        let identity = try await google.signIn()
        return (LinkedAccount(provider: .google, providerUserID: identity.userID, email: identity.email), identity.name)
    }

    /// Links a sign-in to an existing profile (from Settings).
    func link(_ account: LinkedAccount) async throws {
        guard var profile else { return }
        // Keep an email Apple shared before if it isn't sent again.
        var account = account
        if account.email == nil, profile.account?.providerUserID == account.providerUserID { account.email = profile.account?.email }
        profile.account = account
        try await save(profile)
    }

    // MARK: Onboarding and profile

    func completeOnboarding(name: String, account: LinkedAccount?) async throws {
        let defaults = UserDefaults.standard
        let profile = LocalProfile(
            displayName: name,
            languageCode: defaults.string(forKey: AppLanguage.storageKey).flatMap { $0 == AppLanguage.system.rawValue ? nil : $0 },
            digitStyle: defaults.string(forKey: DigitPreference.storageKey).flatMap { $0 == DigitPreference.automatic.rawValue ? nil : $0 },
            account: account)
        try await save(profile)
    }

    func rename(to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var profile, !trimmed.isEmpty, trimmed != profile.displayName else { return }
        profile.displayName = trimmed
        try await save(profile)
    }

    /// Forgets the sign-in on this phone. Groups and the name stay.
    func signOut() async throws {
        guard var profile else { return }
        if profile.account?.provider == .google { await GoogleSignInService.revoke() }
        KeychainStore.deleteAll()
        profile.account = nil
        try await save(profile)
    }

    /// "Delete account": signs out, revokes Google access, clears the Keychain, and with
    /// `eraseData` also deletes every group, expense and payment on this phone.
    func deleteAccount(eraseData: Bool, app: AppModel) async throws {
        try await signOut()
        if eraseData { try await eraseEverything(app: app) }
    }

    /// "Delete all my data": the ledger, history, profile, sign-in and settings on this phone.
    func eraseEverything(app: AppModel) async throws {
        if profile?.account?.provider == .google { await GoogleSignInService.revoke() }
        KeychainStore.deleteAll()
        try await store.eraseEverything()
        for key in [Self.nameKey, AppLanguage.storageKey, DigitPreference.storageKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        profile = nil
        await app.reload()
    }

    // MARK: Export

    /// Writes everything to a JSON file in a temporary folder for the share sheet.
    func exportFile() async throws -> URL {
        let export = try await store.export()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TakaDe export \(day).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: Private

    private func save(_ profile: LocalProfile) async throws {
        try await store.save(profile)
        self.profile = profile
        UserDefaults.standard.set(profile.displayName, forKey: Self.nameKey)
    }

    /// If the person stopped using Apple ID with TakaDe in iOS Settings, forget the link.
    private func checkAppleCredential() async {
        guard let account = profile?.account, account.provider == .apple else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: account.providerUserID)
        if state == .revoked || state == .notFound { try? await signOut() }
    }
}
