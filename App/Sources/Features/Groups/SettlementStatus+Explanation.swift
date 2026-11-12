import Foundation
import TakaDeCore

extension SettlementStatus {
    /// Plain-language status. Never implies a verification that didn't happen.
    var explanation: String {
        switch self {
        case .notStarted: String(localized: "Not started", bundle: .appLanguage)
        case .handoffStarted: String(localized: "Payment app opened, not confirmed", bundle: .appLanguage)
        case .pending: String(localized: "Waiting for confirmation", bundle: .appLanguage)
        case .reportedUnverified: String(localized: "Reported paid, not confirmed yet", bundle: .appLanguage)
        case .acknowledgedByRecipient: String(localized: "Marked received by the person paid", bundle: .appLanguage)
        case .confirmed: String(localized: "Confirmed by the provider", bundle: .appLanguage)
        case .failed: String(localized: "Failed", bundle: .appLanguage)
        case .reversed: String(localized: "Reversed", bundle: .appLanguage)
        }
    }
}
