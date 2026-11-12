import Foundation

/// Which digit shapes to render amounts with.
public enum DigitStyle: String, Codable, Sendable, CaseIterable {
    case latin
    case bengali
}

/// The pieces of a formatted amount, so the UI can render the symbol and
/// decimals smaller (see DESIGN.md section 3) without re-parsing a string.
public struct FormattedMoney: Equatable, Sendable {
    public let sign: String       // "" or "−"
    public let symbol: String     // "৳"
    public let whole: String      // "7,854" or "৭,৮৫৪"
    public let fraction: String   // ".43" or "" when decimals are hidden

    public var plain: String { "\(sign)\(symbol)\u{00A0}\(whole)\(fraction)" }
}

/// Thousands separators. `lakh` groups as 1,00,00,000 (one crore).
public enum Grouping: String, Codable, Sendable, CaseIterable {
    case lakh
    case western
}

public enum MoneyFormatter {
    /// Formats an amount. Defaults to South Asian (lakh/crore) grouping, which is how
    /// amounts are usually written in Bangladesh: 12,34,567. See docs/adr/0006.
    public static func format(
        _ money: Money,
        digits: DigitStyle = .latin,
        grouping: Grouping = .lakh,
        showsZeroFraction: Bool = true,
        symbol customSymbol: String? = nil
    ) -> FormattedMoney {
        let symbol = customSymbol ?? (money.currency.code == "BDT" ? "৳" : money.currency.code)
        let sign = money.isNegative ? "\u{2212}" : ""
        let whole = group(String(Swift.abs(money.majorPart)), grouping)
        var fraction = ""
        if money.currency.minorUnitDigits > 0 && (showsZeroFraction || money.minorPart != 0) {
            let raw = String(money.minorPart)
            fraction = "." + String(repeating: "0", count: money.currency.minorUnitDigits - raw.count) + raw
        }
        let convert: (String) -> String = digits == .bengali ? Digits.toBengali : { $0 }
        return FormattedMoney(sign: sign, symbol: symbol, whole: convert(whole), fraction: convert(fraction))
    }

    private static func group(_ digits: String, _ grouping: Grouping) -> String {
        var result = ""
        for (offset, ch) in digits.reversed().enumerated() {
            let separatorHere: Bool
            switch grouping {
            case .western: separatorHere = offset > 0 && offset % 3 == 0
            case .lakh: separatorHere = offset == 3 || (offset > 3 && (offset - 3) % 2 == 0)
            }
            if separatorHere { result.append(",") }
            result.append(ch)
        }
        return String(result.reversed())
    }
}
