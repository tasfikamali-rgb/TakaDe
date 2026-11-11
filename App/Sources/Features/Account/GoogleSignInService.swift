import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Sign in with Google using the system browser sheet and PKCE (OAuth 2.0 for native apps),
/// with no Google SDK. The app talks only to Google: it reads the person's id, name and email
/// from the ID token and keeps the refresh token in the Keychain so it can be revoked later.
@MainActor
final class GoogleSignInService {
    struct Identity: Sendable {
        let userID: String
        let email: String?
        let name: String?
    }

    enum Failure: Error {
        case couldNotStart, badResponse, stateMismatch, invalidToken
    }

    private static let tokenKey = "google.refreshToken"
    let config: GoogleOAuthConfig
    private var session: ASWebAuthenticationSession?
    private let anchor = PresentationAnchorProvider()

    init(config: GoogleOAuthConfig) {
        self.config = config
    }

    /// Throws `CancellationError` if the person closes the sheet.
    func signIn() async throws -> Identity {
        let verifier = Self.randomURLSafe(32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: config.redirectScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? Failure.badResponse)
                }
            }
            session.presentationContextProvider = anchor
            self.session = session
            if !session.start() { continuation.resume(throwing: Failure.couldNotStart) }
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw Failure.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw Failure.badResponse }

        let tokens = try await exchange(code: code, verifier: verifier)
        let claims = try Self.claims(fromIDToken: tokens.idToken)
        // The token came straight from Google over TLS; check it was issued for this app.
        guard claims.aud == config.clientID, ["accounts.google.com", "https://accounts.google.com"].contains(claims.iss) else {
            throw Failure.invalidToken
        }
        if let refresh = tokens.refreshToken ?? tokens.accessToken {
            KeychainStore.set(refresh, for: Self.tokenKey)
        }
        return Identity(userID: claims.sub, email: claims.email, name: claims.name)
    }

    /// Forgets the sign-in on this phone and asks Google to revoke TakaDe's access.
    static func revoke() async {
        defer { KeychainStore.delete(tokenKey) }
        guard let token = KeychainStore.get(tokenKey) else { return }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Token exchange

    private struct TokenResponse: Decodable {
        let idToken: String
        let accessToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token", accessToken = "access_token", refreshToken = "refresh_token"
        }
    }

    private struct Claims: Decodable {
        let sub: String
        let aud: String
        let iss: String
        let email: String?
        let name: String?
    }

    private func exchange(code: String, verifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func claims(fromIDToken token: String) throws -> Claims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw Failure.invalidToken }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw Failure.invalidToken }
        return try JSONDecoder().decode(Claims.self, from: data)
    }

    // MARK: Helpers

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Gives the browser sheet a window to present from.
final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
