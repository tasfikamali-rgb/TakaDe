import AuthenticationServices
import Foundation
import Observation
import TakaDeCore
import UIKit
import UserNotifications

/// The device owner's profile and their sign-in.
///
/// With a sign-in service configured (Config/Supabase.local.xcconfig, ADR 0016), Create an
/// account and Sign in make or open a TakaDe account that can have Apple, Google, Microsoft
/// and email linked to it. The service holds only the account; groups and expenses stay on
/// this phone. Without one, Apple and Google are linked on this phone only (ADR 0011).
@MainActor
@Observable
final class AccountModel {
    /// Kept in UserDefaults too, because new groups read the name from there.
    static let nameKey = "myDisplayName"

    /// What a sign-in found: the account's name if it has one, and whether this sign-in
    /// just created the account.
    struct SignInOutcome: Sendable {
        var name: String?
        var isNew: Bool
    }

    private(set) var profile: LocalProfile?
    private(set) var identities: [AccountIdentity] = []
    private(set) var isLoaded = false
    /// The profile picture, kept on this phone only (ProfilePhotoFile).
    private(set) var photo: UIImage?
    /// Bumped each time the photo is set or removed, so friends can be sent the new one.
    private(set) var photoRevision = 0
    /// True while the app should ask "Use your Google photo?" (GooglePhotoOffer).
    private(set) var offersGooglePhoto = false
    let store: ProfileRepository
    let google: GoogleSignInService?
    let supabase: SupabaseAuth?

    /// A sign-in made during first launch, before there's a profile to put it on.
    private var pendingLinked: LinkedAccount?
    private var pendingUser: AuthUser?

    init(store: ProfileRepository, google: GoogleOAuthConfig? = .current, supabase: SupabaseConfig? = .current) {
        self.store = store
        self.google = google.map(GoogleSignInService.init(config:))
        self.supabase = supabase.map(SupabaseAuth.init(config:))
    }

    var needsOnboarding: Bool { isLoaded && profile == nil }
    var account: LinkedAccount? { profile?.account }
    var isSignedIn: Bool { profile?.isSignedIn ?? false }
    /// The phone still shows a TakaDe account, but its sign-in to the service has ended, so
    /// TakaDe IDs, chats and shared groups can't reach the server until the person signs in again.
    var signInEnded: Bool {
        guard let supabase, profile?.accountID != nil else { return false }
        return supabase.session == nil
    }
    /// True when accounts live on the sign-in service rather than on this phone only.
    var usesAccountService: Bool { supabase != nil }

    /// The sign-in methods to offer. Apple always comes first (App Review guideline 4.8).
    var availableMethods: [SignInProvider] {
        if let config = supabase?.config {
            var methods: [SignInProvider] = [.apple, .google]
            if config.microsoftEnabled { methods.append(.microsoft) }
            if config.emailEnabled { methods.append(.email) }
            return methods
        }
        return google == nil ? [.apple] : [.apple, .google]
    }

    /// Methods not yet linked to the account, for "Add a sign-in method".
    var linkableMethods: [SignInProvider] {
        guard supabase != nil else { return [] }
        let linked = Set(identities.map(\.provider))
        return availableMethods.filter { !linked.contains($0) }
    }

    func load() async {
        profile = try? await store.profile()
        photo = ProfilePhotoFile.load()
        identities = (try? await store.accountIdentities()) ?? []
        isLoaded = true
        await checkAppleCredential()
        await refreshAccount()
        // Signed in with Google before this question existed: ask once.
        if profile != nil { offerGooglePhotoIfNeeded() }
    }

    // MARK: Sign-in service

    /// Apple, with the raw nonce whose hash went into the request.
    func signInWithApple(_ authorization: ASAuthorization, rawNonce: String) async throws -> SignInOutcome {
        guard let supabase else {
            guard let identity = identity(from: authorization) else { throw SupabaseAuth.Failure.badResponse }
            try await adoptOnDevice(identity.account)
            return SignInOutcome(name: identity.name, isNew: false)
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8)
        else { throw SupabaseAuth.Failure.badResponse }
        let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default, options: []) }
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let user = try await supabase.signInWithApple(idToken: token, rawNonce: rawNonce)
        var outcome = try await adopt(user)
        // Apple shares the name only the first time; it's used here, on the phone only.
        if outcome.name == nil { outcome.name = name }
        return outcome
    }

    /// Google or Microsoft through the browser sheet. Google uses the app's own client and
    /// hands its ID token to the service, so Google's screen says TakaDe.
    func signIn(with provider: SignInProvider) async throws -> SignInOutcome {
        if let supabase, provider == .google, let google {
            let nonce = SupabaseAuth.makeNonce()
            let identity = try await google.signIn(nonce: nonce.hashed, includeProfile: false)
            let outcome = try await adopt(supabase.signInWithGoogle(idToken: identity.idToken, rawNonce: nonce.raw))
            usedGoogle()
            return outcome
        }
        if let supabase, let oauth = SupabaseAuth.Provider(provider) {
            return try await adopt(supabase.signIn(with: oauth))
        }
        guard provider == .google else { throw SupabaseAuth.Failure.couldNotStart }
        let identity = try await signInWithGoogle()
        try await adoptOnDevice(identity.account)
        usedGoogle()
        return SignInOutcome(name: identity.name, isNew: false)
    }

    func sendEmailCode(to email: String, creating: Bool) async throws {
        guard let supabase else { throw SupabaseAuth.Failure.couldNotStart }
        try await supabase.sendEmailCode(to: email, create: creating)
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> SignInOutcome {
        guard let supabase else { throw SupabaseAuth.Failure.couldNotStart }
        return try await adopt(supabase.verifyEmailCode(code, email: email))
    }

    /// Links another sign-in to the account that's signed in.
    func link(_ provider: SignInProvider) async throws {
        if let supabase, provider == .google, let google {
            let nonce = SupabaseAuth.makeNonce()
            let identity = try await google.signIn(nonce: nonce.hashed, includeProfile: false)
            _ = try await adopt(supabase.linkGoogle(idToken: identity.idToken, rawNonce: nonce.raw))
            usedGoogle()
            return
        }
        guard let supabase, let oauth = SupabaseAuth.Provider(provider) else { throw SupabaseAuth.Failure.couldNotStart }
        _ = try await adopt(supabase.link(oauth))
    }

    func linkApple(_ authorization: ASAuthorization, rawNonce: String) async throws {
        guard let supabase, let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8)
        else { throw SupabaseAuth.Failure.couldNotStart }
        _ = try await adopt(supabase.linkApple(idToken: token, rawNonce: rawNonce))
    }

    func addEmail(_ email: String) async throws {
        guard let supabase else { throw SupabaseAuth.Failure.couldNotStart }
        try await supabase.addEmail(email)
    }

    func confirmEmail(code: String, email: String) async throws {
        guard let supabase else { throw SupabaseAuth.Failure.couldNotStart }
        _ = try await adopt(supabase.confirmEmailChange(code: code, email: email))
    }

    /// Removes one sign-in method. The last one can't be removed: sign out or delete the
    /// account instead.
    func unlink(_ identity: AccountIdentity) async throws {
        guard let supabase else { throw SupabaseAuth.Failure.couldNotStart }
        _ = try await adopt(supabase.unlink(identityID: identity.id))
    }

    /// Reads the account again, so links made on another phone show up. Quietly does
    /// nothing offline.
    func refreshAccount() async {
        guard let supabase, supabase.session != nil, profile?.accountID != nil else { return }
        if let user = try? await supabase.currentUser() { _ = try? await adopt(user) }
    }

    /// Keeps what the service returned: on the profile if there is one, otherwise until
    /// first launch finishes.
    private func adopt(_ user: AuthUser) async throws -> SignInOutcome {
        let identities = user.identities.compactMap(Self.accountIdentity(from:))
        if var profile {
            profile.accountID = user.id
            profile.accountEmail = user.email
            profile.account = nil
            try await save(profile)
        } else {
            pendingUser = user
        }
        try await store.replaceAccountIdentities(identities)
        self.identities = identities
        // Names and pictures stay off the server; clear any an older version left there.
        if user.hasPersonalMetadata == true, let supabase {
            Task { _ = try? await supabase.clearPersonalMetadata() }
        }
        return SignInOutcome(name: user.name, isNew: user.isNew)
    }

    private func adoptOnDevice(_ linked: LinkedAccount) async throws {
        if profile != nil { try await link(linked) } else { pendingLinked = linked }
    }

    private static func accountIdentity(from item: AuthUser.Identity) -> AccountIdentity? {
        let provider: SignInProvider
        switch item.provider {
        case "apple": provider = .apple
        case "google": provider = .google
        case "azure": provider = .microsoft
        case "email": provider = .email
        default: return nil
        }
        return AccountIdentity(id: item.identityID ?? item.id, provider: provider, providerUserID: item.id,
                               email: item.email, linkedAt: item.createdAt ?? Date())
    }

    // MARK: Sign-in

    /// Reads what Apple shared. Name and email arrive only on the first sign-in.
    func identity(from authorization: ASAuthorization) -> (account: LinkedAccount, name: String?)? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default, options: []) }
        return (LinkedAccount(provider: .apple, providerUserID: credential.user, email: credential.email),
                name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name : nil)
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

    /// Makes the profile, with whatever sign-in happened during first launch.
    func completeOnboarding(name: String) async throws {
        let defaults = UserDefaults.standard
        let profile = LocalProfile(
            displayName: name,
            languageCode: defaults.string(forKey: AppLanguage.storageKey).flatMap { $0 == AppLanguage.system.rawValue ? nil : $0 },
            account: pendingLinked,
            accountID: pendingUser?.id,
            accountEmail: pendingUser?.email)
        try await save(profile)
        pendingLinked = nil
        pendingUser = nil
    }

    /// Drops a sign-in made during first launch, when the person goes back.
    func discardPendingSignIn() async {
        pendingLinked = nil
        if pendingUser != nil {
            pendingUser = nil
            await supabase?.signOut()
            try? await store.replaceAccountIdentities([])
            identities = []
        }
    }

    /// Sets the name once, for a profile that has none (made by an older version). A name
    /// can never be removed or changed after that (Sabit, 2026-11-12): to use another name,
    /// the person makes a new account.
    func setMissingName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var profile, profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              PersonName.isValid(trimmed) else { return }
        profile.displayName = trimmed
        try await save(profile)
    }

    /// Forgets the sign-in on this phone. Groups and the name stay.
    func signOut() async throws {
        guard var profile else { return }
        if profile.account?.provider == .google { await GoogleSignInService.revoke() }
        await supabase?.signOut()
        KeychainStore.deleteAll()
        profile.account = nil
        profile.accountID = nil
        profile.accountEmail = nil
        try await save(profile)
        try await store.replaceAccountIdentities([])
        identities = []
    }

    /// "Delete account": deletes the TakaDe account on the sign-in service (when there is
    /// one), signs out, revokes Google access, clears the Keychain, and with `eraseData`
    /// also deletes every group, expense and payment on this phone. If the service can't be
    /// reached, nothing is removed, so the person can try again.
    func deleteAccount(eraseData: Bool, app: AppModel) async throws {
        if let supabase, profile?.accountID != nil {
            try await supabase.deleteAccount()
        }
        try await signOut()
        if eraseData { try await eraseEverything(app: app) }
    }

    /// "Delete all my data": the ledger, history, profile, sign-in and settings on this phone.
    func eraseEverything(app: AppModel) async throws {
        if profile?.account?.provider == .google { await GoogleSignInService.revoke() }
        // Signs out of the account here; the account itself stays until "Delete account".
        await supabase?.signOut()
        KeychainStore.deleteAllIncludingSynced()
        // Shared groups' keys and the sharing sign-in go too.
        SyncKeychain.deleteAll()
        ReceiptPhotos.deleteAll()
        try await store.eraseEverything()
        for key in [Self.nameKey, AppLanguage.storageKey, DigitPreference.storageKey, HomeRegion.storageKey,
                    GroupNotifications.enabledKey, GroupNotifications.promptDismissedKey,
                    CurrencyCatalog.codeKey, CurrencyCatalog.showsForeignKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        ExchangeRateStore.removeCache()
        // Notifications already shown can name people and amounts.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        ProfilePhotoFile.remove()
        GroupPhotoFile.removeAll()
        MemberPhotoFile.removeAll()
        MemberPhotos.reset()
        FriendPhotos.removeAll()
        photo = nil
        offersGooglePhoto = false
        profile = nil
        identities = []
        await app.reload()
    }

    // MARK: Profile photo

    /// True when Google can be asked for this person's photo.
    var canUseGooglePhoto: Bool {
        google != nil && (profile?.account?.provider == .google || pendingLinked?.provider == .google
                          || identities.contains { $0.provider == .google })
    }

    private static let googlePhotoAskedKey = "account.googlePhotoAsked"

    /// After signing in with Google (Sabit, 2026-11-12): ask whether to use the Google photo,
    /// when there's no photo yet and the question hasn't been answered since that sign-in.
    func offerGooglePhotoIfNeeded() {
        guard canUseGooglePhoto, photo == nil, !UserDefaults.standard.bool(forKey: Self.googlePhotoAskedKey) else { return }
        offersGooglePhoto = true
    }

    /// Either answer counts; it's asked again only after the next Google sign-in.
    func answeredGooglePhotoOffer() {
        UserDefaults.standard.set(true, forKey: Self.googlePhotoAskedKey)
        offersGooglePhoto = false
    }

    /// A fresh Google sign-in or link: the photo question may be asked again.
    private func usedGoogle() {
        UserDefaults.standard.removeObject(forKey: Self.googlePhotoAskedKey)
    }

    /// The Google email this account uses, so Google's sheet can skip choosing an account.
    private var googleEmail: String? {
        identities.first { $0.provider == .google }?.email
            ?? (profile?.account?.provider == .google ? profile?.account?.email : nil)
            ?? (pendingLinked?.provider == .google ? pendingLinked?.email : nil)
    }

    /// "Use my Google photo" (Sabit, 2026-11-12): asks Google directly, in its own sheet, for
    /// the profile photo and saves it on this phone like a picked one. Nothing goes to
    /// TakaDe's sign-in service, so the account still holds no name or photo.
    func useGooglePhoto() async throws {
        guard let google else { throw GoogleSignInService.Failure.couldNotStart }
        let identity = try await google.signIn(includeProfile: true, loginHint: googleEmail)
        guard let picture = identity.picture, picture.scheme == "https",
              picture.host?.hasSuffix(".googleusercontent.com") == true else { throw GoogleSignInService.Failure.badResponse }
        // Google's address ends in a size such as "=s96-c"; ask for a sharper one.
        let text = picture.absoluteString
        let sized = text.range(of: "=s\\d+(-c)?$", options: .regularExpression)
            .map { text.replacingCharacters(in: $0, with: "=s512-c") } ?? text
        let (data, response) = try await URLSession.shared.data(from: URL(string: sized) ?? picture)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000 else {
            throw GoogleSignInService.Failure.badResponse
        }
        try await setPhoto(data)
    }

    func setPhoto(_ data: Data) async throws {
        photo = try await ProfilePhotoFile.save(data)
        photoRevision += 1
    }

    func removePhoto() {
        ProfilePhotoFile.remove()
        photo = nil
        photoRevision += 1
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
