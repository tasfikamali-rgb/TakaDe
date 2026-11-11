import Foundation
import TakaDeCore

extension PaymentHandle.Rail {
    var label: String {
        switch self {
        case .bkash: "bKash"
        case .nagad: "Nagad"
        case .rocket: "Rocket"
        case .upay: "upay"
        case .bank: String(localized: "Bank account", bundle: .appLanguage)
        }
    }

    /// The settlement method that matches this rail, for preselecting "Paid with".
    var settlementMethod: SettlementMethod {
        switch self {
        case .bkash: .bkash
        case .nagad: .nagad
        case .rocket: .rocket
        case .upay: .upay
        case .bank: .bankTransfer
        }
    }
}

extension PaymentHandle {
    /// "01712-345678" for wallets, so the number is easy to read back; bank details as typed.
    var displayHandle: String {
        guard rail.isWallet, handle.count == 11 else { return handle }
        return handle.prefix(5) + "-" + handle.dropFirst(5)
    }
}
