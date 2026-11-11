import Foundation
import TakaDeCore

/// In-app language choice. "System" follows the device setting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", bengali = "bn"
    static let storageKey = "appLanguage"
    var id: String { rawValue }
    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en_BD")
        case .bengali: Locale(identifier: "bn_BD")
        }
    }
    /// Shown in its own language so people can always find it.
    var nativeName: String {
        switch self {
        case .system: String(localized: "Same as device")
        case .english: "English"
        case .bengali: "বাংলা"
        }
    }
}

extension DigitStyle {
    static let storageKey = "digitStyle"
}
