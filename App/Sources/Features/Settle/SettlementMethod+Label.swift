import Foundation
import TakaDeCore

extension SettlementMethod {
    var label: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .bkash: "bKash"
        case .upay: "upay"
        case .bankTransfer: String(localized: "Bank transfer")
        case .other: String(localized: "Other")
        }
    }
}
