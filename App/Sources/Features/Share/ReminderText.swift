import Foundation
import TakaDeCore

/// A short, friendly nudge for someone who owes you, sent through any chat app from the
/// share sheet. Holds only this one debt and how to pay you; nothing else from the group.
enum ReminderText {
    static func make(to name: String, amount: Money, group: String, handles: [PaymentHandle]) -> String {
        let total = MoneyFormatter.format(amount).plain
        var lines = [String(localized: "Hi \(name), a quick reminder from \(group): \(total) to me when you get a chance.", bundle: .appLanguage, comment: "Reminder message: debtor name, group name, amount")]
        for handle in handles {
            lines.append("\(handle.rail.label): \(handle.displayHandle)")
        }
        lines.append("")
        lines.append(String(localized: "Worked out with TakaDe", bundle: .appLanguage))
        return lines.joined(separator: "\n")
    }
}
