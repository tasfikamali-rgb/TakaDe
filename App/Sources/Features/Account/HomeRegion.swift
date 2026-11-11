import Foundation

/// "Where are you from?" in first launch. Kept on this phone only (UserDefaults); it picks
/// the suggested language now and the default currency once TakaDe supports more than taka.
/// Every UN member state is offered, for Bangladeshis abroad too (Sabit, 2026-11-11).
enum HomeRegion {
    static let storageKey = "homeRegion"
    static let elsewhere = "other"

    /// ISO 3166-1 alpha-2 codes of the 193 UN member states.
    static let unMembers: [String] = [
        "AF", "AL", "DZ", "AD", "AO", "AG", "AR", "AM", "AU", "AT", "AZ", "BS", "BH", "BD", "BB", "BY",
        "BE", "BZ", "BJ", "BT", "BO", "BA", "BW", "BR", "BN", "BG", "BF", "BI", "CV", "KH", "CM", "CA",
        "CF", "TD", "CL", "CN", "CO", "KM", "CG", "CR", "CI", "HR", "CU", "CY", "CZ", "KP", "CD", "DK",
        "DJ", "DM", "DO", "EC", "EG", "SV", "GQ", "ER", "EE", "SZ", "ET", "FJ", "FI", "FR", "GA", "GM",
        "GE", "DE", "GH", "GR", "GD", "GT", "GN", "GW", "GY", "HT", "HN", "HU", "IS", "IN", "ID", "IR",
        "IQ", "IE", "IL", "IT", "JM", "JP", "JO", "KZ", "KE", "KI", "KW", "KG", "LA", "LV", "LB", "LS",
        "LR", "LY", "LI", "LT", "LU", "MG", "MW", "MY", "MV", "ML", "MT", "MH", "MR", "MU", "MX", "FM",
        "MC", "MN", "ME", "MA", "MZ", "MM", "NA", "NR", "NP", "NL", "NZ", "NI", "NE", "NG", "MK", "NO",
        "OM", "PK", "PW", "PA", "PG", "PY", "PE", "PH", "PL", "PT", "QA", "KR", "MD", "RO", "RU", "RW",
        "KN", "LC", "VC", "WS", "SM", "ST", "SA", "SN", "RS", "SC", "SL", "SG", "SK", "SI", "SB", "SO",
        "ZA", "SS", "ES", "LK", "SD", "SR", "SE", "CH", "SY", "TJ", "TH", "TL", "TG", "TO", "TT", "TN",
        "TR", "TM", "TV", "UG", "UA", "AE", "GB", "TZ", "US", "UY", "UZ", "VU", "VE", "VN", "YE", "ZM",
        "ZW"
    ]

    /// The phone's region when it's a UN member, otherwise Bangladesh.
    static var suggested: String {
        let phone = Locale.current.region?.identifier ?? ""
        return unMembers.contains(phone) ? phone : "BD"
    }

    /// Bangladesh first, then the phone's own country, then the rest by name in the
    /// app's language, then "Somewhere else" for places that aren't UN members.
    static func ordered(in locale: Locale) -> [String] {
        let phone = Locale.current.region?.identifier ?? ""
        let top = ["BD"] + (phone != "BD" && unMembers.contains(phone) ? [phone] : [])
        let rest = unMembers.filter { !top.contains($0) }
            .sorted { name($0, in: locale).localizedStandardCompare(name($1, in: locale)) == .orderedAscending }
        return top + rest + [elsewhere]
    }

    static func name(_ code: String, in locale: Locale) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// Matches the name in the app's language or in English, so "Bangladesh" finds বাংলাদেশ.
    static func matches(_ code: String, query: String, in locale: Locale) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        guard code != elsewhere else { return false }
        let english = Locale(identifier: "en").localizedString(forRegionCode: code) ?? code
        return [name(code, in: locale), english, code].contains { $0.localizedStandardContains(query) }
    }

    static func flag(_ code: String) -> String {
        guard code != elsewhere else { return "🌏" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }
}
