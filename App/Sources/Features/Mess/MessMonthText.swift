import Foundation
import TakaDeCore

/// The month's closing, for the mess's chat: bazar, meals, meal rate and what each
/// person's meals cost. Holds nothing else from the group.
enum MessMonthText {
    static func make(_ summary: MessMonthSummary, group: ExpenseGroup) -> String {
        let monthName = summary.month.startDate().formatted(.dateTime.month(.wide).year())
        var lines = [String(localized: "\(group.name): \(monthName)", bundle: .appLanguage, comment: "Mess month heading: group name, month")]
        lines.append(String(localized: "Bazar: \(MoneyFormatter.format(summary.bazarTotal).plain)", bundle: .appLanguage))
        lines.append(String(localized: "Meals: \(MealNumber.text(summary.totalHalfMeals, digits: .latin))", bundle: .appLanguage))
        if let rate = summary.mealRate {
            lines.append(String(localized: "Meal rate: \(MoneyFormatter.format(rate).plain)", bundle: .appLanguage))
        }
        lines.append("")
        for member in group.members {
            let meals = MealNumber.text(summary.halfMeals[member.id] ?? 0, digits: .latin)
            let cost = MoneyFormatter.format(summary.mealCost[member.id] ?? .zero(summary.bazarTotal.currency)).plain
            lines.append(String(localized: "\(group.storedName(of: member.id)): \(meals) meals, \(cost)", bundle: .appLanguage, comment: "Mess line: name, meals, cost"))
        }
        lines.append("")
        lines.append(String(localized: "Worked out with TakaDe", bundle: .appLanguage))
        return lines.joined(separator: "\n")
    }
}
