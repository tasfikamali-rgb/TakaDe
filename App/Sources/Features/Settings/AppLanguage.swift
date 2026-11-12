import Foundation

/// In-app language choice. "System" follows the device setting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case bengali = "bn"

    static let storageKey = "appLanguage"
    var id: String { rawValue }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en_BD")
        case .bengali: Locale(identifier: "bn_BD")
        }
    }

    /// Whether TakaDe is showing Bengali, chosen in the app or inherited from the phone.
    static var usesBengaliScript: Bool {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        switch AppLanguage(rawValue: raw) ?? .system {
        case .bengali: return true
        case .english: return false
        case .system: return Bundle.main.preferredLocalizations.first == "bn"
        }
    }

    /// The only two choices offered (Sabit, 2026-11-11): no "Same as phone".
    static let choices: [AppLanguage] = [.bengali, .english]

    /// The language actually showing. Before anyone picks, "system" resolves to the
    /// phone's language, so a two-option picker always has one selected.
    var choice: AppLanguage {
        get {
            guard self == .system else { return self }
            return Bundle.main.preferredLocalizations.first == "bn" ? .bengali : .english
        }
        set { self = newValue }
    }

    /// Each language is shown in its own script so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: String(localized: "Same as phone", bundle: .appLanguage)
        case .english: "English"
        case .bengali: "বাংলা"
        }
    }
}
