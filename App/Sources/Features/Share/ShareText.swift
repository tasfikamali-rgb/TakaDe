import Foundation
import TakaDeCore

/// Plain text that goes with the image, for chats that drop images or for copy-paste.
enum ShareText {
    static func make(_ summary: GroupSummary, digits: DigitStyle) -> String {
        var lines = [summary.groupName]
        if summary.isSettled {
            lines.append(String(localized: "Everyone is settled up"))
        } else {
            for line in summary.lines {
                let amount = MoneyFormatter.format(line.amount, digits: digits).plain
                lines.append(String(localized: "\(line.from) pays \(line.to) \(amount)", comment: "Share text line: payer, receiver, amount"))
            }
        }
        lines.append("")
        lines.append(String(localized: "Worked out with TakaDe"))
        return lines.joined(separator: "\n")
    }
}
