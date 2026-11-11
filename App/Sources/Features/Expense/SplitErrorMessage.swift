import Foundation
import TakaDeCore

/// Says what went wrong and how to fix it, without apologizing.
enum SplitErrorMessage {
    static func text(for error: SplitError) -> String {
        switch error {
        case .exactAmountsDoNotMatchTotal(let expected, let actual):
            let diff = (try? expected.subtracting(actual)) ?? .zero()
            let amount = MoneyFormatter.format(diff.magnitude).plain
            return diff.isNegative
                ? String(localized: "The amounts add up to \(amount) more than the total")
                : String(localized: "\(amount) still needs someone to pay it")
        case .percentagesDoNotSumTo100:
            return String(localized: "Percentages need to add up to 100")
        case .noParticipants:
            return String(localized: "Pick at least one person")
        case .nonPositiveTotal:
            return String(localized: "Enter an amount above zero")
        default:
            return String(localized: "Check the amounts")
        }
    }
}
