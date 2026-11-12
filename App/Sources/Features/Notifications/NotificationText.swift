import Foundation
import TakaDeCore

/// The words of a group notification, in the language chosen in TakaDe. Names are shown
/// exactly as entered; amounts use the language's digits.
enum NotificationText {
    static var locked: String {
        String(localized: "Something changed in a shared group. Open TakaDe to see it.", bundle: .appLanguage,
               comment: "Notification body when the app lock is on, so nothing private shows")
    }

    static func body(for notice: GroupNotice, in group: ExpenseGroup) -> String {
        let digits: DigitStyle = AppLanguage.usesBengaliScript ? .bengali : .latin
        var lines: [String] = []
        if let first = notice.events.first {
            lines.append(sentence(for: first, in: group, digits: digits))
        }
        if notice.events.count > 1 {
            let more = String(notice.events.count - 1)
            let count = digits == .bengali ? Digits.toBengali(more) : more
            lines.append(String(localized: "+ \(count) more", bundle: .appLanguage, comment: "Notification: how many other changes came with the first one"))
        }
        if let balance = notice.myBalance {
            lines.append(standing(balance, digits: digits))
        }
        return lines.joined(separator: "\n")
    }

    static func sentence(for event: GroupNotice.Event, in group: ExpenseGroup, digits: DigitStyle) -> String {
        func name(_ id: MemberID?) -> String {
            id.flatMap { group.member($0)?.shownName } ?? String(localized: "Someone", bundle: .appLanguage, comment: "Notification: a change whose author isn't known")
        }
        func money(_ amount: Money) -> String { MoneyFormatter.format(amount, digits: digits).plain }

        switch event {
        case let .expense(title, action, by, share):
            let who = name(by)
            switch (action, share) {
            case (.created, let share?):
                return String(localized: "\(who) added “\(title)”. Your share is \(money(share)).", bundle: .appLanguage, comment: "Notification: person, expense title, my share")
            case (.created, nil):
                return String(localized: "\(who) added “\(title)”.", bundle: .appLanguage, comment: "Notification: person, expense title")
            case (.deleted, _):
                return String(localized: "\(who) deleted “\(title)”.", bundle: .appLanguage, comment: "Notification: person, expense title")
            case (.restored, _):
                return String(localized: "\(who) brought back “\(title)”.", bundle: .appLanguage, comment: "Notification: person, expense title")
            case (_, let share?):
                return String(localized: "\(who) changed “\(title)”. Your share is now \(money(share)).", bundle: .appLanguage, comment: "Notification: person, expense title, my share")
            case (_, nil):
                return String(localized: "\(who) changed “\(title)”.", bundle: .appLanguage, comment: "Notification: person, expense title")
            }
        case let .paidYou(by, amount):
            return String(localized: "\(name(by)) says they paid you \(money(amount)).", bundle: .appLanguage, comment: "Notification: person, amount. Their word, not verified")
        case let .markedReceived(by, amount):
            return String(localized: "\(name(by)) marked your \(money(amount)) payment as received.", bundle: .appLanguage, comment: "Notification: person, amount")
        case let .paymentChanged(by, amount):
            return String(localized: "\(name(by)) changed a payment of \(money(amount)).", bundle: .appLanguage, comment: "Notification: person, amount")
        case let .othersPayment(from, to, amount):
            return String(localized: "\(name(from)) says they paid \(name(to)) \(money(amount)).", bundle: .appLanguage, comment: "Notification: payer, person paid, amount. A payment between two other people, their word, not verified")
        }
    }

    static func standing(_ balance: Money, digits: DigitStyle) -> String {
        let amount = MoneyFormatter.format(Money(minorUnits: abs(balance.minorUnits), currency: balance.currency), digits: digits).plain
        if balance.minorUnits > 0 {
            return String(localized: "In this group you're owed \(amount).", bundle: .appLanguage, comment: "Notification: my balance in the group")
        } else if balance.minorUnits < 0 {
            return String(localized: "In this group you owe \(amount).", bundle: .appLanguage, comment: "Notification: my balance in the group")
        }
        return String(localized: "You're settled up in this group.", bundle: .appLanguage, comment: "Notification: my balance in the group")
    }
}
