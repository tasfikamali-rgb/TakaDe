import Foundation

/// One thing an edit changed, found by comparing the copy before and after. Activity and
/// History use it to say "Amount ৳500 → ৳650" instead of just "edited".
public enum ExpenseChange: Hashable, Sendable {
    case title(from: String, to: String)
    case total(from: Money, to: Money)
    case date(from: Date, to: Date)
    /// Someone else paid, or the amounts several people paid changed.
    case paidBy
    /// Who shares it, or how it's divided, changed.
    case split
    case category
    case receipt

    /// What changed between two versions of the same expense, in a fixed order. Empty
    /// when nothing people see changed (a delete or restore, for example).
    public static func between(_ old: Expense, _ new: Expense, calendar: Calendar = .current) -> [ExpenseChange] {
        var changes: [ExpenseChange] = []
        if old.title != new.title { changes.append(.title(from: old.title, to: new.title)) }
        if old.total != new.total { changes.append(.total(from: old.total, to: new.total)) }
        if !calendar.isDate(old.occurredAt, inSameDayAs: new.occurredAt) { changes.append(.date(from: old.occurredAt, to: new.occurredAt)) }
        if payersChanged(old, new) { changes.append(.paidBy) }
        if splitChanged(old, new) { changes.append(.split) }
        if old.category != new.category { changes.append(.category) }
        if old.receiptID != new.receiptID { changes.append(.receipt) }
        return changes
    }

    /// One payer paying the whole amount stays "the same payer" when only the total moves.
    private static func payersChanged(_ old: Expense, _ new: Expense) -> Bool {
        guard Set(old.paidBy.keys) == Set(new.paidBy.keys) else { return true }
        return old.paidBy.count > 1 && old.paidBy != new.paidBy
    }

    /// An equal or shares split keeps its rule when only the total moves, so that alone
    /// isn't a split change. Exact amounts always move with the total, so for those the
    /// split counts as changed only if the people changed or the total stayed the same.
    private static func splitChanged(_ old: Expense, _ new: Expense) -> Bool {
        if old.splitRule == new.splitRule { return false }
        if case .exact(let a) = old.splitRule, case .exact(let b) = new.splitRule, old.total != new.total {
            return Set(a.keys) != Set(b.keys)
        }
        return true
    }
}

/// One thing an edit to a payment changed.
public enum SettlementChange: Hashable, Sendable {
    case amount(from: Money, to: Money)
    case method(from: SettlementMethod, to: SettlementMethod)
    case reference
    case status(from: SettlementStatus, to: SettlementStatus)

    public static func between(_ old: Settlement, _ new: Settlement) -> [SettlementChange] {
        var changes: [SettlementChange] = []
        if old.amount != new.amount { changes.append(.amount(from: old.amount, to: new.amount)) }
        if old.method != new.method { changes.append(.method(from: old.method, to: new.method)) }
        if Settlement.normalizedReference(old.userReference) != Settlement.normalizedReference(new.userReference) {
            changes.append(.reference)
        }
        if old.status != new.status { changes.append(.status(from: old.status, to: new.status)) }
        return changes
    }
}
