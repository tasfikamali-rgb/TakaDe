import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import TakaDeCore
import UIKit

/// TakaDe accounts through Supabase Auth's REST API, with no Supabase SDK, so nothing else
/// joins the app's privacy manifest. Email sign-in uses a 6-digit code (no passwords),
/// Apple passes its ID token, and Google and Microsoft go through the system browser sheet
/// with PKCE. The session is kept in the Keychain only.
@MainActor
@Observable
final class SupabaseAuth {
    enum Provider: String, Sendable {
        case google, azure

        init?(_ provider: SignInProvider) {
            switch provider {
            case .google: self = .google
            case .microsoft: self = .azure
            case .apple, .email: return nil
            }
        }
    }

    enum Failure: Error, Equatable {
        case badResponse
        case codeRejected
        case notSignedIn
        case couldNotStart
        case lastSignInMethod
        /// The server's sign-up hook refused a throwaway ("10-minute") email address.
        case disposableEmail
        case server(status: Int, code: String?)

        /// The marker the server puts in its message when it refuses a throwaway address
        /// (supabase/migrations/*_block_disposable_emails.sql).
        static let disposableEmailMarker = "disposable_email_not_allowed"
    }

    let config: SupabaseConfig
    private(set) var session: AuthSession?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = PresentationAnchorProvider()
    /// The one token refresh in flight. Every caller waits for it instead of sending its own,
    /// because the service gives out each refresh token once.
    @ObservationIgnored private var refreshing: Task<Void, Error>?

    init(config: SupabaseConfig) {
        self.config = config
        session = AuthSession.load()
    }

    // MARK: Email code

    /// Sends a 6-digit code. When signing in (`create == false`) no account is made, and the
    /// caller shows the same message either way, so nobody learns whether an email has an
    /// account.
    /// No name goes with it: the name stays on the phone (Sabit, 2026-11-11).
    func sendEmailCode(to email: String, create: Bool) async throws {
        let body: [String: Any] = ["email": email, "create_user": create]
        do {
            _ = try await post("otp", body: body)
        } catch Failure.server(let status, _) where !create && (400...422).contains(status) {
            // "Signups not allowed" for an unknown email: stay quiet about it.
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthUser {
        do {
            let json = try await post("verify", body: ["type": "email", "email": email, "token": code])
            return try adopt(json)
        } catch Failure.server(let status, _) where (400...422).contains(status) {
            throw Failure.codeRejected
        }
    }

    // MARK: Apple

    /// A fresh nonce for a Sign in with Apple request: Apple gets the hash, the service the
    /// raw value, so a stolen ID token can't be replayed.
    nonisolated static func makeNonce() -> (raw: String, hashed: String) {
        let raw = randomURLSafe(32)
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }

    /// Apple's name, when it shares one, stays on the phone; it isn't sent here.
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthUser {
        let json = try await post("token?grant_type=id_token", body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce])
        return try adopt(json)
    }

    /// Links an Apple sign-in to the account that's signed in now.
    func linkApple(idToken: String, rawNonce: String) async throws -> AuthUser {
        guard session != nil else { throw Failure.notSignedIn }
        let json = try await post("token?grant_type=id_token",
                                  body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce, "link_identity": true],
                                  authorized: true)
        return try adopt(json)
    }

    /// Google, with the ID token from the app's own iOS client (GoogleSignInService), so
    /// Google's screen shows TakaDe instead of this service's address. The iOS client id
    /// must be in the Google provider's Client IDs in Supabase.
    func signInWithGoogle(idToken: String, rawNonce: String) async throws -> AuthUser {
        let json = try await post("token?grant_type=id_token", body: ["provider": "google", "id_token": idToken, "nonce": rawNonce])
        return try adopt(json)
    }

    /// Links a Google sign-in (an ID token, as above) to the account that's signed in now.
    func linkGoogle(idToken: String, rawNonce: String) async throws -> AuthUser {
        guard session != nil else { throw Failure.notSignedIn }
        let json = try await post("token?grant_type=id_token",
                                  body: ["provider": "google", "id_token": idToken, "nonce": rawNonce, "link_identity": true],
                                  authorized: true)
        return try adopt(json)
    }

    // MARK: Google and Microsoft in the browser

    func signIn(with provider: Provider) async throws -> AuthUser {
        let pkce = Self.makePKCE()
        var components = URLComponents(url: config.authURL.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = authorizeItems(provider, challenge: pkce.challenge)
        let code = try await runBrowser(components.url!)
        return try await exchange(code: code, verifier: pkce.verifier)
    }

    /// Links Google or Microsoft to the account that's signed in now.
    func link(_ provider: Provider) async throws -> AuthUser {
        guard session != nil else { throw Failure.notSignedIn }
        let pkce = Self.makePKCE()
        var components = URLComponents(url: config.authURL.appendingPathComponent("user/identities/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = authorizeItems(provider, challenge: pkce.challenge) + [.init(name: "skip_http_redirect", value: "true")]
        let json = try await request(components.url!, method: "GET", body: nil, authorized: true)
        guard let link = (json["url"] as? String).flatMap(URL.init(string:)) else { throw Failure.badResponse }
        let code = try await runBrowser(link)
        return try await exchange(code: code, verifier: pkce.verifier)
    }

    // MARK: Account

    func currentUser() async throws -> AuthUser {
        let json = try await request(config.authURL.appendingPathComponent("user"), method: "GET", body: nil, authorized: true)
        let user = try Self.user(from: json)
        session?.user = user
        session?.store()
        return user
    }

    /// The account keeps no name or picture (Sabit, 2026-11-11): names stay on the phone
    /// and in the groups. Clears what earlier versions, or Google's profile, put there.
    nonisolated static let personalMetadataKeys = ["name", "full_name", "picture", "avatar_url"]

    func clearPersonalMetadata() async throws -> AuthUser {
        try await updateUser(["data": Dictionary(uniqueKeysWithValues: Self.personalMetadataKeys.map { ($0, NSNull()) })])
    }

    /// Adds an email address to the account. A code goes to the new address; confirm it
    /// with `confirmEmailChange`.
    func addEmail(_ email: String) async throws {
        _ = try await updateUser(["email": email])
    }

    func confirmEmailChange(code: String, email: String) async throws -> AuthUser {
        do {
            _ = try await post("verify", body: ["type": "email_change", "email": email, "token": code], authorized: true)
        } catch Failure.server(let status, _) where (400...422).contains(status) {
            throw Failure.codeRejected
        }
        return try await currentUser()
    }

    func unlink(identityID: String) async throws -> AuthUser {
        let user = try await currentUser()
        guard user.identities.count > 1 else { throw Failure.lastSignInMethod }
        _ = try await request(config.authURL.appendingPathComponent("user/identities/\(identityID)"), method: "DELETE", body: nil, authorized: true)
        return try await currentUser()
    }

    func signOut() async {
        if session != nil {
            _ = try? await request(config.authURL.appendingPathComponent("logout"), method: "POST", body: [:], authorized: true)
        }
        session = nil
        AuthSession.clear()
    }

    /// Deletes the account on the service through the `delete-account` function, which holds
    /// the service-role key server-side. Then forgets the session here.
    func deleteAccount() async throws {
        _ = try await request(config.functionsURL.appendingPathComponent("delete-account"), method: "POST", body: [:], authorized: true)
        session = nil
        AuthSession.clear()
    }

    // MARK: Private

    private func authorizeItems(_ provider: Provider, challenge: String) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "provider", value: provider.rawValue),
            .init(name: "redirect_to", value: SupabaseConfig.redirectURL),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "s256"),
        ]
        // Microsoft doesn't send an email unless asked.
        if provider == .azure { items.append(.init(name: "scopes", value: "email")) }
        return items
    }

    private func runBrowser(_ url: URL) async throws -> String {
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SupabaseConfig.callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? Failure.badResponse)
                }
            }
            session.presentationContextProvider = anchor
            self.webSession = session
            if !session.start() { continuation.resume(throwing: Failure.couldNotStart) }
        }
        webSession = nil
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        // Errors can come back in the fragment ("#error=...&error_description=...").
        if let fragment = components?.fragment {
            var parsed = URLComponents()
            parsed.query = fragment
            items += parsed.queryItems ?? []
        }
        if items.contains(where: { $0.name == "error_description" && ($0.value ?? "").contains(Failure.disposableEmailMarker) }) {
            throw Failure.disposableEmail
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw Failure.badResponse }
        return code
    }

    private func exchange(code: String, verifier: String) async throws -> AuthUser {
        let json = try await post("token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
        return try adopt(json)
    }

    private func updateUser(_ body: [String: Any]) async throws -> AuthUser {
        let json = try await request(config.authURL.appendingPathComponent("user"), method: "PUT", body: body, authorized: true)
        let user = try Self.user(from: json)
        session?.user = user
        session?.store()
        return user
    }

    /// Keeps the session from a token response.
    private func adopt(_ json: [String: Any]) throws -> AuthUser {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let userJSON = json["user"] as? [String: Any] else { throw Failure.badResponse }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let user = try Self.user(from: userJSON)
        let session = AuthSession(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn), user: user)
        session.store()
        self.session = session
        return user
    }

    /// A database call (PostgREST) as the signed-in account, for TakaDe IDs. Returns the raw
    /// response body; failures carry the database's error code.
    func rest(_ path: String, method: String, body: Any? = nil, prefer: String? = nil) async throws -> Data {
        try await refreshIfNeeded()
        guard let token = session?.accessToken,
              let url = URL(string: config.baseURL.appendingPathComponent("rest/v1").absoluteString + "/" + path)
        else { throw Failure.notSignedIn }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw Failure.server(status: http.statusCode, code: json["code"] as? String)
        }
        return data
    }

    /// A current access token, refreshed first when it's about to expire. For the Realtime
    /// connection, which sends it itself.
    func accessToken() async throws -> String {
        try await refreshIfNeeded()
        guard let token = session?.accessToken else { throw Failure.notSignedIn }
        return token
    }

    private func refreshIfNeeded() async throws {
        // Read at launch only; if iOS started the app before the phone was first unlocked,
        // the Keychain was closed then. Look again before calling it signed out.
        if session == nil { session = AuthSession.load() }
        guard let current = session else { throw Failure.notSignedIn }
        guard current.isExpiring else { return }
        if let refreshing { return try await refreshing.value }
        let task = Task { try await self.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        try await task.value
    }

    /// Swaps the refresh token for new tokens. The service retires the old refresh token the
    /// moment it answers, so the answer must not be lost: the app asks iOS for time to finish
    /// if it goes to the background, and a dropped connection is retried once at once (the
    /// service answers a quick repeat of the same token with the same new tokens).
    private func refresh(_ current: AuthSession) async throws {
        let background = UIApplication.shared.beginBackgroundTask(withName: "Sign-in refresh")
        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
        let body = ["refresh_token": current.refreshToken]
        do {
            let json: [String: Any]
            do {
                json = try await post("token?grant_type=refresh_token", body: body)
            } catch let error as URLError where Self.mayHaveReachedServer(error) {
                json = try await post("token?grant_type=refresh_token", body: body)
            }
            // Signed out, or into another account, while this was out: drop the answer.
            guard session?.refreshToken == current.refreshToken else { return }
            _ = try adopt(json)
        } catch Failure.server(let status, _) where (400...401).contains(status) {
            // A newer sign-in replaced this one while we waited: keep it.
            guard session?.refreshToken == current.refreshToken else { return }
            // The refresh token was revoked or used up: the person has to sign in again.
            session = nil
            AuthSession.clear()
            throw Failure.notSignedIn
        }
    }

    /// Errors after which the request may still have reached the service.
    nonisolated static func mayHaveReachedServer(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .timedOut, .cancelled, .backgroundSessionWasDisconnected: true
        default: false
        }
    }

    private func post(_ path: String, body: [String: Any], authorized: Bool = false) async throws -> [String: Any] {
        guard let url = URL(string: config.authURL.absoluteString + "/" + path) else { throw Failure.badResponse }
        return try await request(url, method: "POST", body: body, authorized: authorized)
    }

    private func request(_ url: URL, method: String, body: [String: Any]?, authorized: Bool) async throws -> [String: Any] {
        if authorized { try await refreshIfNeeded() }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let message = [json["msg"], json["message"], json["error_description"]].compactMap { $0 as? String }.joined(separator: " ")
            if message.contains(Failure.disposableEmailMarker) { throw Failure.disposableEmail }
            throw Failure.server(status: http.statusCode, code: (json["error_code"] as? String) ?? (json["error"] as? String))
        }
        return json
    }

    nonisolated static func user(from json: [String: Any]) throws -> AuthUser {
        guard let id = json["id"] as? String else { throw Failure.badResponse }
        let metadata = json["user_metadata"] as? [String: Any] ?? [:]
        let name = (metadata["name"] as? String) ?? (metadata["full_name"] as? String)
        let identities = (json["identities"] as? [[String: Any]] ?? []).compactMap { item -> AuthUser.Identity? in
            guard let provider = item["provider"] as? String else { return nil }
            let data = item["identity_data"] as? [String: Any] ?? [:]
            let providerID = (item["provider_id"] as? String) ?? (data["sub"] as? String) ?? (item["id"] as? String) ?? ""
            return AuthUser.Identity(identityID: item["identity_id"] as? String ?? item["id"] as? String, id: providerID,
                                     provider: provider, email: data["email"] as? String, createdAt: date(item["created_at"]))
        }
        let hasPersonal = personalMetadataKeys.contains { (metadata[$0] as? String)?.isEmpty == false }
        return AuthUser(id: id, email: json["email"] as? String, name: name?.isEmpty == false ? name : nil,
                        createdAt: date(json["created_at"]), lastSignInAt: date(json["last_sign_in_at"]), identities: identities,
                        hasPersonalMetadata: hasPersonal)
    }

    /// Supabase writes times like 2026-11-11T22:08:44.123456Z; the fraction is dropped.
    nonisolated static func date(_ value: Any?) -> Date? {
        guard var text = value as? String else { return nil }
        if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            text.removeSubrange(dot..<end)
        }
        return ISO8601DateFormatter().date(from: text)
    }

    nonisolated static func makePKCE() -> (verifier: String, challenge: String) {
        let verifier = randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return (verifier, challenge)
    }

    nonisolated static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
