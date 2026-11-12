import Foundation
import TakaDeCore

/// How VoiceOver reads an amount: "7854 taka 43 poisha".
enum SpokenAmount {
    static func text(for money: Money) -> String {
        if money.currency.code != Currency.bdt.code {
            // "12.50 British pounds": iOS words other currencies itself, in the app's language.
            let value = Decimal(money.minorUnits) / Decimal(money.currency.minorUnitsPerMajor)
            let locale = AppLanguage.usesBengaliScript ? Locale(identifier: "bn_BD") : Locale(identifier: "en_BD")
            return value.formatted(.currency(code: money.currency.code).locale(locale).presentation(.fullName))
        }
        let whole = abs(money.majorPart).formatted()
        let sign = money.isNegative ? String(localized: "minus", bundle: .appLanguage) + " " : ""
        if money.minorPart == 0 {
            return sign + String(localized: "\(whole) taka", bundle: .appLanguage, comment: "Spoken amount. %@ is the whole number")
        }
        return sign + String(localized: "\(whole) taka \(money.minorPart) poisha", bundle: .appLanguage, comment: "Spoken amount. First is taka, second is poisha")
    }
}
