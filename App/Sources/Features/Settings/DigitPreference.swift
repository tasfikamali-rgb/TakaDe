import Foundation
import TakaDeCore

/// Digits follow the language (Sabit, 2026-11-11): Bengali digits (১২৩) in Bangla and
/// 1 2 3 in English. There's no separate setting; `storageKey` is the old setting's key,
/// kept only so "Delete all my data" clears it from earlier installs.
enum DigitPreference {
    static let storageKey = "digitPreference"

    static func style(for locale: Locale) -> DigitStyle {
        locale.language.languageCode?.identifier == "bn" ? .bengali : .latin
    }
}
