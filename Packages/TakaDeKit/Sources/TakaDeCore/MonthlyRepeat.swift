import Foundation

/// Adds the monthly copies of repeating expenses (rent, internet, a maid's salary) that are
/// due by now. Each copy is an ordinary expense, so it can be edited or deleted like any other.
public enum MonthlyRepeat {
    /// At most this many months are caught up at once, so a phone left unopened for years
    /// doesn't flood a group.
    public static let maxCatchUpMonths = 12

    /// The copies that should exist but don't. A month that already has a copy, even a
    /// deleted one, is skipped, so deleting one month's rent doesn't bring it back.
    public static func dueCopies(of expenses: [Expense], now: Date = Date(), calendar: Calendar = .current) -> [Expense] {
        let copiedMonths: [ExpenseID: Set<MessMonth>] = expenses.reduce(into: [:]) { result, expense in
            guard let source = expense.repeatOf else { return }
            result[source, default: []].insert(MessMonth(containing: expense.occurredAt, calendar: calendar))
        }
        let thisMonth = MessMonth(containing: now, calendar: calendar)
        var copies: [Expense] = []
        for source in expenses where source.repeatsMonthly && source.deletedAt == nil {
            let first = MessMonth(containing: source.occurredAt, calendar: calendar).next()
            guard first <= thisMonth else { continue }
            var month = first
            var months: [MessMonth] = []
            while month <= thisMonth {
                months.append(month)
                month = month.next()
            }
            for month in months.suffix(maxCatchUpMonths) where !(copiedMonths[source.id]?.contains(month) ?? false) {
                guard let date = sameDay(as: source.occurredAt, in: month, calendar: calendar), date <= now else { continue }
                if let copy = try? Expense(groupID: source.groupID, title: source.title, total: source.total,
                                           paidBy: source.paidBy, splitRule: source.splitRule, occurredAt: date,
                                           note: source.note, category: source.category, repeatOf: source.id) {
                    copies.append(copy)
                }
            }
        }
        return copies.sorted { $0.occurredAt < $1.occurredAt }
    }

    /// The same day and time in another month, moved to the month's last day when it's
    /// shorter (rent on the 31st lands on 30 November).
    static func sameDay(as date: Date, in month: MessMonth, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.day, .hour, .minute, .second], from: date)
        let start = month.startDate(calendar: calendar)
        guard let days = calendar.range(of: .day, in: .month, for: start)?.count else { return nil }
        parts.year = month.year
        parts.month = month.month
        parts.day = min(parts.day ?? 1, days)
        return calendar.date(from: parts)
    }
}
