import Foundation

/// Which Supabase project the app talks to: the main one, or the spare that a nightly job
/// refills from the main one's backup (docs/adr/0034-packed-changes-and-backups.md).
///
/// Both projects are built into the app. A tiny public file, kept outside Supabase so it
/// still loads when Supabase is down, says which one to use: `{"use":"main"}` or
/// `{"use":"spare"}`. The file can only pick between the two built-in projects, so whoever
/// can change it can't point the app anywhere else. The choice is read when the app opens
/// and takes effect the next time it opens.
enum ServerSwitch {
    enum Choice: String { case main, spare }

    private static let storeKey = "takade.server"

    /// The choice saved from the switch file. Main when there's no spare in this build.
    static var current: Choice {
        guard SupabaseConfig.spareConfigured,
              let saved = UserDefaults.standard.string(forKey: storeKey).flatMap(Choice.init(rawValue:)) else { return .main }
        return saved
    }

    /// True once after the app starts using a different project than last time.
    static func takeChanged() -> Bool {
        let now = current.rawValue
        let before = UserDefaults.standard.string(forKey: usedKey)
        UserDefaults.standard.set(now, forKey: usedKey)
        return before != nil && before != now
    }

    private static let usedKey = "takade.server.used"

    /// Reads the switch file and saves the choice. Quiet on any failure: the last saved
    /// choice stays.
    static func refresh() async {
        guard SupabaseConfig.spareConfigured, let url = switchURL else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1024,
              let body = try? JSONDecoder().decode([String: String].self, from: data),
              let choice = body["use"].flatMap(Choice.init(rawValue:)) else { return }
        UserDefaults.standard.set(choice.rawValue, forKey: storeKey)
    }

    /// From the build setting TAKADE_SERVER_SWITCH_URL, without "https://" (xcconfig reads
    /// "//" as a comment). Empty turns the switch off.
    private static var switchURL: URL? {
        let raw = (Bundle.main.infoDictionary?["TakaDeServerSwitchURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !raw.isEmpty, !raw.contains("://") else { return nil }
        return URL(string: "https://\(raw)")
    }
}
