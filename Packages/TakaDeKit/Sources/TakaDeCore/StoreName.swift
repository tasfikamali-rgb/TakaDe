import Foundation

/// The shop name sent for store insights when a person has said yes (ADR 0032): the name
/// they confirmed on the receipt review screen, trimmed to single spaces and lower case so
/// "SHWAPNO" and "Shwapno " count as one shop. Nothing else from the receipt is sent.
public enum StoreName {
    public static let maxLength = 60

    /// The name to count, or nil when there's nothing worth counting: empty, one character,
    /// longer than 60 characters, or no letter at all (a phone number, a total).
    public static func normalized(_ name: String?) -> String? {
        guard let name else { return nil }
        let words = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .lowercased()
        guard (2...maxLength).contains(words.count), words.contains(where: \.isLetter) else { return nil }
        return words
    }

    /// Two-letter country code for the count, "ZZ" when unknown or "Somewhere else".
    public static func countryCode(_ stored: String?) -> String {
        guard let stored, stored.count == 2,
              stored.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return "ZZ" }
        return stored
    }
}
