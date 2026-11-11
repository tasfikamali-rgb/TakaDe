import Foundation
import TakaDeCore

/// Says what went wrong and how to fix it, without apologizing.
enum SplitErrorMessage {
    static func leftToAssign(expected: Money, actual: Money) -> String {
        let diff = (try? expected.subtracting(actual)) ?? .zero()
        let amount = MoneyFormatter.format(diff).plain
        return String(localized: "\(amount) left to assign", bundle: .appLanguage)
    }

    static func text(for error: SplitError) -> String {
        switch error {
        case .exactAmountsDoNotMatchTotal(let expected, let actual):
            let diff = (try? expected.subtracting(actual)) ?? .zero()
            let amount = MoneyFormatter.format(diff.magnitude).plain
            return diff.isNegative
                ? String(localized: "The amounts add up to \(amount) more than the total", bundle: .appLanguage)
                : String(localized: "\(amount) still needs someone to pay it", bundle: .appLanguage)
        case .percentagesDoNotSumTo100:
            return String(localized: "Percentages need to add up to 100", bundle: .appLanguage)
        case .noParticipants:
            return String(localized: "Pick at least one person", bundle: .appLanguage)
        case .adjustmentsExceedTotal:
            return String(localized: "The extras add up to more than the total", bundle: .appLanguage)
        case .negativeAmount:
            return String(localized: "Someone's share would be below zero. Check the minus amounts.", bundle: .appLanguage)
        case .nonPositiveTotal:
            return String(localized: "Enter an amount above zero", bundle: .appLanguage)
        default:
            return String(localized: "Check the amounts", bundle: .appLanguage)
        }
    }
}
