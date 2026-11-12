import Foundation

/// The rule for people's names (Sabit, 2026-11-11): proper names only, no emoji. A name may
/// use letters from any script, so Bangla, English and names of Bangladeshis abroad all
/// work, plus the marks those scripts need (Bangla vowel signs, hasanta), spaces, hyphens,
/// apostrophes and dots. Names are checked, never changed: what's accepted is kept exactly
/// as typed.
public enum PersonName {
    public enum Problem: Error, Equatable, Sendable {
        case empty
        /// Emoji, symbols, digits or other characters that aren't part of a name.
        case notAName
        case tooLong
    }

    public static let maxLength = 60

    /// Spaces, hyphens, apostrophes and dots, including the curly apostrophe phones insert
    /// and the zero-width joiners that some Bangla spellings use.
    private static let punctuation: Set<Unicode.Scalar> = [
        " ", "-", "\u{2010}", "\u{2011}", "'", "\u{2019}", ".", "\u{200C}", "\u{200D}",
    ]

    public static func problem(with name: String) -> Problem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= maxLength else { return .tooLong }
        var hasLetter = false
        for scalar in trimmed.unicodeScalars {
            // Emoji presentation is checked first: some emoji are made of letters or digits.
            if scalar.properties.isEmojiPresentation || scalar.value == 0xFE0F || scalar.value == 0x20E3 {
                return .notAName
            }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                hasLetter = true
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                if !punctuation.contains(scalar) { return .notAName }
            }
        }
        return hasLetter ? nil : .notAName
    }

    public static func isValid(_ name: String) -> Bool { problem(with: name) == nil }
}
