import Foundation
import TakaDeCore

/// Which digits to show amounts in. Automatic uses Bengali digits in the Bengali interface.
enum DigitPreference: String, CaseIterable, Identifiable {
    case automatic, latin, bengali

    static let storageKey = "digitPreference"
    var id: String { rawValue }

    func resolved(for locale: Locale) -> DigitStyle {
        switch self {
        case .latin: .latin
        case .bengali: .bengali
        case .automatic: locale.language.languageCode?.identifier == "bn" ? .bengali : .latin
        }
    }
}
