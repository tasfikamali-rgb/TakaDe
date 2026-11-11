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

    /// Each language is shown in its own script so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: String(localized: "Same as phone")
        case .english: "English"
        case .bengali: "বাংলা"
        }
    }
}
