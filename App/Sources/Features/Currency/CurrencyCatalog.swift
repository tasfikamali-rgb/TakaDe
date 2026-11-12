import Foundation
import TakaDeCore

/// Currencies the header can show the balance in, and how each one looks. Display only:
/// the ledger keeps every amount in the currency it was recorded in (ADR 27).
enum CurrencyCatalog {
    /// The foreign currency the header toggle switches to. Kept on this phone only.
    static let codeKey = "displayCurrency"
    /// Whether the header is showing that currency instead of taka.
    static let showsForeignKey = "showsDisplayCurrency"

    /// Where Bangladeshis abroad mostly live and send money from, then the big ones.
    static let suggested = ["GBP", "USD", "EUR", "SAR", "AED", "QAR", "KWD", "OMR", "MYR", "SGD", "CAD", "AUD", "INR", "JPY"]

    /// Currencies some country uses today, per iOS. Keeps retired ones (Deutsche Mark),
    /// crypto and metals in the rate table out of the picker.
    static let knownISO: Set<String> = Set(Locale.Region.isoRegions.compactMap {
        Locale(identifier: "und_\($0.identifier)").currency?.identifier
    })

    /// The first guess: the money of the country picked at first launch, or US dollars for
    /// people in Bangladesh (or who haven't picked).
    static var defaultCode: String {
        let region = UserDefaults.standard.string(forKey: HomeRegion.storageKey) ?? HomeRegion.suggested
        guard region != "BD", region != HomeRegion.elsewhere,
              let code = Locale(identifier: "und_\(region)").currency?.identifier,
              code != "BDT", knownISO.contains(code)
        else { return "USD" }
        return code
    }

    /// The code as a `Currency` with ISO decimals (JPY 0, KWD 3, most 2).
    static func currency(_ code: String) -> Currency {
        if code == "BDT" { return .bdt }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = code
        return Currency(code: code, minorUnitDigits: min(max(formatter.maximumFractionDigits, 0), 4))
    }

    /// "£", "$", "€", "₹", "CA$"; the code itself when there's no clear sign ("SAR").
    static func symbol(_ code: String) -> String {
        if code == "BDT" { return "৳" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = code
        let sign = formatter.currencySymbol ?? code
        return sign.isEmpty ? code : sign
    }

    /// The flag of the country the currency belongs to (Sabit, 2026-11-12): 🇧🇩 for BDT,
    /// 🇬🇧 for GBP, 🇪🇺 for EUR. Every currency in the picker gets one: ISO codes start with
    /// the country's code, so that's tried first, then any country or territory iOS says
    /// uses it (🇰🇾 for KYD). Shared regional currencies use the flag picked in `shared`.
    static func flag(_ code: String) -> String? { flags[code] }

    /// Money several places share, with no flag of its own: the country of the issuing
    /// central bank, or the biggest user.
    private static let shared: [String: String] = [
        "EUR": "EU", // euro area
        "XAF": "CM", // Central African CFA franc: Cameroon, the biggest CEMAC economy
        "XOF": "SN", // West African CFA franc: BCEAO is in Dakar
        "XCD": "KN", // East Caribbean dollar: ECCB is in Basseterre
        "XPF": "PF", // CFP franc: French Polynesia
        "XCG": "CW", // Caribbean guilder: Curaçao
        "ANG": "CW", // Netherlands Antillean guilder, which XCG replaced
        "USD": "US",
        "CHF": "CH",
        "AUD": "AU",
        "NZD": "NZ",
        "INR": "IN",
        "ZAR": "ZA",
        "GBP": "GB",
        "DKK": "DK",
        "NOK": "NO",
        "ILS": "IL",
        "MAD": "MA",
    ]

    /// Built once: a few hundred lookups, so scrolling the list doesn't repeat them.
    /// UN members come before territories, so a shared currency shows the country's flag.
    private static let flags: [String: String] = {
        var regionFor = shared
        let un = Set(HomeRegion.unMembers)
        let territories = Locale.Region.isoRegions.map(\.identifier).filter {
            $0.count == 2 && $0.allSatisfy(\.isUppercase) && !un.contains($0)
                && !["EU", "EZ", "UN", "QO", "XK", "XA", "XB"].contains($0)
        }
        for (regions, isUN) in [(HomeRegion.unMembers, true), (territories, false)] {
            for region in regions {
                guard let code = Locale(identifier: "und_\(region)").currency?.identifier,
                      shared[code] == nil else { continue }
                guard let current = regionFor[code] else { regionFor[code] = region; continue }
                // A country whose code the currency starts with beats one that only uses it.
                if isUN, code.hasPrefix(region), !code.hasPrefix(current) { regionFor[code] = region }
            }
        }
        return regionFor.mapValues(HomeRegion.flag)
    }()

    /// "British Pound" / "ব্রিটিশ পাউন্ড", in the app's language.
    static func name(_ code: String, in locale: Locale) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// Matches the name in the app's language or English, the code, or the sign.
    static func matches(_ code: String, query: String, in locale: Locale) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let english = Locale(identifier: "en").localizedString(forCurrencyCode: code) ?? code
        return [name(code, in: locale), english, code, symbol(code)].contains { $0.localizedStandardContains(query) }
    }
}
