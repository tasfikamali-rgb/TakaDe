import Foundation
import TakaDeCore

/// Turns a group's change log into readable lines. Each saved change keeps a copy of the
/// expense or payment after it; comparing it with the copy before says what an edit
/// changed. Only what's already in the group's history is used: nothing new is collected.
enum ActivityFeed {
    /// `events` newest first, as `history(of:)` returns them. `entities` limits what's
    /// shown (Activity shows expenses and payments); nil shows everything.
    static func items(for events: [AuditEvent], in group: ExpenseGroup, entities: Set<AuditEvent.Entity>? = nil,
                      locale: Locale) -> [ActivityItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let digits = DigitPreference.style(for: locale)
        var before: [String: Data] = [:]
        var items: [ActivityItem] = []
        for event in events.reversed() {
            let key = "\(event.entity.rawValue)/\(event.entityID.uuidString)"
            defer { before[key] = event.snapshot }
            guard entities?.contains(event.entity) ?? true else { continue }
            let writer = Writer(group: group, decoder: decoder, digits: digits, locale: locale)
            items.append(writer.item(for: event, previous: before[key]))
        }
        return items.reversed()
    }

    private struct Writer {
        let group: ExpenseGroup
        let decoder: JSONDecoder
        let digits: DigitStyle
        let locale: Locale

        func item(for event: AuditEvent, previous: Data?) -> ActivityItem {
            switch event.entity {
            case .expense:
                if let expense = try? decoder.decode(Expense.self, from: event.snapshot) {
                    let old = previous.flatMap { try? decoder.decode(Expense.self, from: $0) }
                    return expenseItem(event, expense, old: old)
                }
            case .settlement:
                if let settlement = try? decoder.decode(Settlement.self, from: event.snapshot) {
                    let old = previous.flatMap { try? decoder.decode(Settlement.self, from: $0) }
                    return settlementItem(event, settlement, old: old)
                }
            case .group, .member, .meal:
                break
            }
            return ActivityItem(id: event.id, group: group, occurredAt: event.occurredAt,
                                headline: HistoryDescription.text(for: event, in: group), details: [], amount: nil, isRemoved: false)
        }

        private var someone: String { String(localized: "Someone", bundle: .appLanguage) }

        private func actorName(_ event: AuditEvent) -> String {
            event.actor.map(group.displayName(of:)) ?? someone
        }

        private func expenseItem(_ event: AuditEvent, _ expense: Expense, old: Expense?) -> ActivityItem {
            let who = actorName(event), title = expense.title
            var details: [String] = []
            let headline: String
            let broughtBack = old?.deletedAt != nil && expense.deletedAt == nil
            switch event.action {
            case .created:
                headline = String(localized: "\(who) added \(title)", bundle: .appLanguage)
            case .deleted:
                headline = String(localized: "\(who) deleted \(title)", bundle: .appLanguage)
            case .restored:
                headline = String(localized: "\(who) brought back \(title)", bundle: .appLanguage)
            case .edited, .statusChanged:
                if broughtBack {
                    headline = String(localized: "\(who) brought back \(title)", bundle: .appLanguage)
                } else if old?.deletedAt == nil, expense.deletedAt != nil {
                    headline = String(localized: "\(who) deleted \(title)", bundle: .appLanguage)
                } else {
                    headline = String(localized: "\(who) edited \(title)", bundle: .appLanguage)
                    if let old { details = ExpenseChange.between(old, expense).map(describe) }
                }
            }
            return ActivityItem(id: event.id, group: group, occurredAt: event.occurredAt, headline: headline, details: details,
                                amount: expense.total, isRemoved: expense.deletedAt != nil)
        }

        private func settlementItem(_ event: AuditEvent, _ settlement: Settlement, old: Settlement?) -> ActivityItem {
            let who = actorName(event)
            let headline: String
            var details = [String(localized: "\(group.displayName(of: settlement.from)) paid \(group.displayName(of: settlement.to))", bundle: .appLanguage)]
            switch event.action {
            case .created:
                headline = String(localized: "\(who) recorded a payment", bundle: .appLanguage)
                details.append(settlement.status.explanation)
            default:
                headline = String(localized: "\(who) edited a payment", bundle: .appLanguage)
                if let old { details += SettlementChange.between(old, settlement).map(describe) }
            }
            return ActivityItem(id: event.id, group: group, occurredAt: event.occurredAt, headline: headline, details: details,
                                amount: settlement.amount, isRemoved: settlement.status == .reversed || settlement.status == .failed)
        }

        private func money(_ value: Money) -> String {
            MoneyFormatter.format(value, digits: digits).plain
        }

        private func day(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
        }

        private func describe(_ change: ExpenseChange) -> String {
            switch change {
            case .title(let from, let to):
                return String(localized: "Name: \(from) → \(to)", bundle: .appLanguage)
            case .total(let from, let to):
                return String(localized: "Amount: \(money(from)) → \(money(to))", bundle: .appLanguage)
            case .date(let from, let to):
                return String(localized: "Date: \(day(from)) → \(day(to))", bundle: .appLanguage)
            case .paidBy:
                return String(localized: "Who paid changed", bundle: .appLanguage)
            case .split:
                return String(localized: "Split changed", bundle: .appLanguage)
            case .category:
                return String(localized: "Category changed", bundle: .appLanguage)
            case .receipt:
                return String(localized: "Receipt photo changed", bundle: .appLanguage)
            }
        }

        private func describe(_ change: SettlementChange) -> String {
            switch change {
            case .amount(let from, let to):
                return String(localized: "Amount: \(money(from)) → \(money(to))", bundle: .appLanguage)
            case .method(let from, let to):
                return String(localized: "Paid with: \(from.label) → \(to.label)", bundle: .appLanguage)
            case .reference:
                return String(localized: "Transaction ID changed", bundle: .appLanguage)
            case .status(_, let to):
                return to.explanation
            }
        }
    }
}
