import Foundation

/// A currency the ledger can hold. Amounts are always stored as integer minor units.
public struct Currency: Hashable, Codable, Sendable {
    /// ISO 4217 code, e.g. "BDT".
    public let code: String
    /// Number of minor-unit digits. BDT has 2 (100 poisha = 1 taka).
    public let minorUnitDigits: Int

    public init(code: String, minorUnitDigits: Int) {
        precondition(minorUnitDigits >= 0 && minorUnitDigits <= 4, "Unsupported minor unit precision")
        self.code = code
        self.minorUnitDigits = minorUnitDigits
    }

    /// Bangladesh Taka. The initial assumption, not a hard limit.
    public static let bdt = Currency(code: "BDT", minorUnitDigits: 2)

    /// 10^minorUnitDigits.
    public var minorUnitsPerMajor: Int64 {
        var value: Int64 = 1
        for _ in 0..<minorUnitDigits { value *= 10 }
        return value
    }
}

public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch(Currency, Currency)
    case overflow
    case negativeAmount
    case invalidInput(String)
}

/// An exact amount of money. Never uses floating point.
public struct Money: Hashable, Codable, Sendable, Comparable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency = .bdt) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func zero(_ currency: Currency = .bdt) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    /// Parses a user-entered decimal string such as "1,250.5" or "১২৫০.৫০" (Bengali digits).
    /// Rejects more fractional digits than the currency allows rather than silently rounding.
    public static func parse(_ text: String, currency: Currency = .bdt) throws -> Money {
        let normalized = Digits.toLatin(text)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "৳", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { throw MoneyError.invalidInput(text) }

        var negative = false
        var body = Substring(normalized)
        if body.first == "-" { negative = true; body = body.dropFirst() }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              let whole = parts.first,
              !whole.isEmpty || parts.count == 2,
              whole.allSatisfy(\.isASCIIDigit)
        else { throw MoneyError.invalidInput(text) }

        let fraction = parts.count == 2 ? parts[1] : ""
        guard fraction.allSatisfy(\.isASCIIDigit),
              fraction.count <= currency.minorUnitDigits
        else { throw MoneyError.invalidInput(text) }

        let paddedFraction = String(fraction) + String(repeating: "0", count: currency.minorUnitDigits - fraction.count)
        guard let wholeValue = Int64(whole.isEmpty ? "0" : String(whole)),
              let fractionValue = Int64(paddedFraction.isEmpty ? "0" : paddedFraction)
        else { throw MoneyError.overflow }

        let (scaled, o1) = wholeValue.multipliedReportingOverflow(by: currency.minorUnitsPerMajor)
        let (total, o2) = scaled.addingReportingOverflow(fractionValue)
        guard !o1, !o2 else { throw MoneyError.overflow }
        return Money(minorUnits: negative ? -total : total, currency: currency)
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }
    public var magnitude: Money { Money(minorUnits: Swift.abs(minorUnits), currency: currency) }
    public var negated: Money { Money(minorUnits: -minorUnits, currency: currency) }

    public func adding(_ other: Money) throws -> Money {
        guard currency == other.currency else { throw MoneyError.currencyMismatch(currency, other.currency) }
        let (sum, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: sum, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try adding(other.negated)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Comparing money in different currencies")
        return lhs.minorUnits < rhs.minorUnits
    }

    /// Whole (major) units, truncated toward zero.
    public var majorPart: Int64 { minorUnits / currency.minorUnitsPerMajor }
    /// Minor units after the decimal point, always non-negative.
    public var minorPart: Int64 { Swift.abs(minorUnits % currency.minorUnitsPerMajor) }
}

public extension Sequence where Element == Money {
    /// Sums amounts, all of which must share `currency`.
    func sum(in currency: Currency) throws -> Money {
        try reduce(Money.zero(currency)) { try $0.adding($1) }
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
