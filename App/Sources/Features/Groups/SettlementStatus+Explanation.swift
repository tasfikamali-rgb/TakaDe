import Foundation
import TakaDeCore

extension SettlementStatus {
    /// Plain-language status. Never implies a verification that didn't happen.
    var explanation: String {
        switch self {
        case .notStarted: String(localized: "Not started")
        case .handoffStarted: String(localized: "Payment app opened, not confirmed")
        case .pending: String(localized: "Waiting for confirmation")
        case .reportedUnverified: String(localized: "Recorded by you, not verified")
        case .acknowledgedByRecipient: String(localized: "Marked received by the person paid")
        case .confirmed: String(localized: "Confirmed by the provider")
        case .failed: String(localized: "Failed")
        case .reversed: String(localized: "Reversed")
        }
    }
}
