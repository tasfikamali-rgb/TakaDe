import Foundation

/// The Google OAuth client for iOS. It comes from the owner's Google Cloud project and is
/// set in Config/Google.local.xcconfig (not committed). Without it, "Continue with Google"
/// is hidden rather than failing.
struct GoogleOAuthConfig: Sendable {
    /// e.g. "1234-abcd.apps.googleusercontent.com"
    let clientID: String

    /// Google's redirect scheme for iOS clients: the client id reversed.
    var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    static var current: GoogleOAuthConfig? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "TakaDeGoogleClientID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard value.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return GoogleOAuthConfig(clientID: value)
    }
}
