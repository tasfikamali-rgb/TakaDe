import Foundation
import TakaDeCore

extension SettlementMethod {
    var label: String {
        switch self {
        case .cash: String(localized: "Cash", bundle: .appLanguage)
        case .bkash: "bKash"
        case .nagad: "Nagad"
        case .rocket: "Rocket"
        case .upay: "upay"
        case .bankTransfer: String(localized: "Bank transfer", bundle: .appLanguage)
        case .other: String(localized: "Other", bundle: .appLanguage)
        }
    }
}
