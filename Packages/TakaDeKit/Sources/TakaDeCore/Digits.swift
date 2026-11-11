import Foundation

/// Conversion between Latin (0-9) and Bengali (০-৯) digits.
/// Only digits are touched; names and other text are never altered.
public enum Digits {
    private static let bengali: [Character] = ["০", "১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯"]

    public static func toLatin(_ text: String) -> String {
        String(text.map { ch in
            if let index = bengali.firstIndex(of: ch) { return Character(String(index)) }
            return ch
        })
    }

    public static func toBengali(_ text: String) -> String {
        String(text.map { ch in
            if let value = ch.wholeNumberValue, ch.isASCIIDigit { return bengali[value] }
            return ch
        })
    }
}
