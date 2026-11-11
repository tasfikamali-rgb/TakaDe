import Foundation

/// Where TakaDe accounts live (docs/adr/0016-accounts-on-supabase.md). The project host and
/// its public anon key come from Config/Supabase.local.xcconfig, which isn't committed.
/// Without them, Create an account and Sign in fall back to the on-device Apple and Google
/// link, and email and Microsoft are hidden. The anon key is public by design: row-level
/// security, not the key, protects data. The service-role key never goes in the app.
struct SupabaseConfig: Sendable {
    /// e.g. https://abcdefghijkl.supabase.co
    let baseURL: URL
    let anonKey: String

    /// The app's own callback for Google and Microsoft sign-in. Add it to the project's
    /// Authentication > URL Configuration > Redirect URLs.
    static let callbackScheme = "takade"
    static let redirectURL = "takade://auth-callback"

    var authURL: URL { baseURL.appendingPathComponent("auth/v1") }
    var functionsURL: URL { baseURL.appendingPathComponent("functions/v1") }

    static var current: SupabaseConfig? {
        let info = Bundle.main.infoDictionary ?? [:]
        let host = (info["TakaDeSupabaseHost"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let key = (info["TakaDeSupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        // xcconfig treats "//" as a comment, so only the host is configured.
        guard !host.isEmpty, !key.isEmpty, !host.contains("/"), let url = URL(string: "https://\(host)") else { return nil }
        return SupabaseConfig(baseURL: url, anonKey: key)
    }
}
