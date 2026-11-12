import Foundation

/// A day's exchange-rate table: how many units of each currency one unit of `base` buys.
///
/// Used only to *show* an amount in another currency. The ledger keeps every amount in the
/// currency it was recorded in; a converted figure is never stored or used to settle.
/// See docs/adr/0027-display-currency-rates.md.
public struct ExchangeRates: Codable, Equatable, Sendable {
    /// ISO 4217 code of the table's base, upper case, e.g. "BDT".
    public let base: String
    /// The day the source published the rates, "YYYY-MM-DD".
    public let date: String
    /// Upper-case code -> units of that currency per one unit of `base`. Always > 0.
    public let rates: [String: Decimal]

    public init(base: String, date: String, rates: [String: Decimal]) {
        self.base = base.uppercased()
        self.date = date
        self.rates = rates
    }

    public enum ParseError: Error, Equatable, Sendable {
        case tooLarge
        case malformed
        case missingBase
        case badDate
    }

    /// Largest table accepted. The real one is about 6 KB.
    public static let maxBytes = 256 * 1024

    /// Parses the fawazahmed0 currency-api shape: `{"date":"2026-11-11","bdt":{"usd":0.0079,…}}`.
    /// The download is untrusted: anything that isn't a positive number is dropped, and the
    /// table is rejected if it lacks a date or the base.
    public static func parse(_ data: Data, base: String) throws -> ExchangeRates {
        guard data.count <= maxBytes else { throw ParseError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.malformed
        }
        guard let date = object["date"] as? String, isDay(date) else { throw ParseError.badDate }
        guard let table = object[base.lowercased()] as? [String: Any] else { throw ParseError.missingBase }

        var rates: [String: Decimal] = [:]
        for (key, value) in table {
            guard key.count >= 2, key.count <= 10, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
                  let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let rate = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0, rate.isFinite
            else { continue }
            rates[key.uppercased()] = rate
        }
        guard !rates.isEmpty else { throw ParseError.missingBase }
        rates[base.uppercased()] = 1
        return ExchangeRates(base: base, date: date, rates: rates)
    }

    /// Codes in the table that are also in `known` (ISO currencies), minus the base.
    /// Keeps crypto, metals and retired currencies out of the picker.
    public func currencyCodes(knownISO known: Set<String>) -> [String] {
        let excluded: Set<String> = [base, "XAU", "XAG", "XPT", "XPD", "XDR"]
        return rates.keys.filter { known.contains($0) && !excluded.contains($0) }.sorted()
    }

    /// How many units of `target` one unit of `source` buys, or nil when either is missing.
    public func rate(from source: String, to target: String) -> Decimal? {
        guard let s = rates[source.uppercased()], let t = rates[target.uppercased()] else { return nil }
        return t / s
    }

    /// `money` shown in `target`, rounded half away from zero to the target's minor units.
    /// Nil when a rate is missing or the result doesn't fit.
    public func convert(_ money: Money, to target: Currency) -> Money? {
        if money.currency.code == target.code { return Money(minorUnits: money.minorUnits, currency: target) }
        guard let rate = rate(from: money.currency.code, to: target.code) else { return nil }
        var exact = Decimal(money.minorUnits) * rate * Decimal(target.minorUnitsPerMajor) / Decimal(money.currency.minorUnitsPerMajor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        guard rounded.isFinite,
              rounded <= Decimal(Int64.max), rounded >= Decimal(Int64.min + 1)
        else { return nil }
        return Money(minorUnits: NSDecimalNumber(decimal: rounded).int64Value, currency: target)
    }

    private static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return false }
        return true
    }
}
