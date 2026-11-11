import Foundation

/// A group's expenses and payments as a CSV file for Excel, Numbers or Google Sheets.
/// One row per expense or payment, one share column per person. Amounts are plain numbers
/// with Latin digits so spreadsheets can add them up. Names and titles are kept exactly as
/// typed, except that a leading = + - or @ gets a ' in front so a spreadsheet never runs
/// it as a formula.
public enum LedgerCSV {
    public struct Labels: Sendable {
        public var date = "Date", type = "Type", title = "Title", category = "Category"
        public var amount = "Amount", currency = "Currency", paidBy = "Paid by", status = "Status"
        public var expense = "Expense", payment = "Payment"
        public init() {}
    }

    public static func make(group: ExpenseGroup, expenses: [Expense], settlements: [Settlement], labels: Labels = Labels(),
                            categoryName: (ExpenseCategory) -> String = { $0.rawValue },
                            statusName: (SettlementStatus) -> String = { $0.rawValue },
                            calendar: Calendar = .current) -> String {
        let members = group.members
        var rows: [[String]] = [[labels.date, labels.type, labels.title, labels.category, labels.amount, labels.currency, labels.paidBy]
            + members.map(\.displayName) + [labels.status]]

        struct Line { let date: Date; let cells: [String] }
        var lines: [Line] = []
        for expense in expenses where expense.deletedAt == nil {
            let payers = members.compactMap { member in
                expense.paidBy[member.id].map { "\(member.displayName): \(number($0))" }
            }.joined(separator: "; ")
            let shares = members.map { member in expense.allocation.shares[member.id].map(number) ?? "" }
            lines.append(Line(date: expense.occurredAt, cells: [day(expense.occurredAt, calendar), labels.expense, expense.title,
                                                                expense.category.map(categoryName) ?? "", number(expense.total),
                                                                expense.total.currency.code, payers] + shares + [""]))
        }
        for settlement in settlements {
            let from = group.members.first { $0.id == settlement.from }?.displayName ?? ""
            let to = group.members.first { $0.id == settlement.to }?.displayName ?? ""
            let shares = members.map { $0.id == settlement.to ? number(settlement.amount) : "" }
            lines.append(Line(date: settlement.createdAt, cells: [day(settlement.createdAt, calendar), labels.payment, "\(from) → \(to)", "",
                                                                  number(settlement.amount), settlement.amount.currency.code,
                                                                  "\(from): \(number(settlement.amount))"] + shares + [statusName(settlement.status)]))
        }
        rows += lines.sorted { $0.date < $1.date }.map(\.cells)
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// 1250.5 taka becomes "1250.50"; always Latin digits and a dot.
    static func number(_ money: Money) -> String {
        let digits = money.currency.minorUnitDigits
        let sign = money.minorUnits < 0 ? "-" : ""
        guard digits > 0 else { return sign + String(Swift.abs(money.majorPart)) }
        let fraction = String(money.minorPart)
        return sign + String(Swift.abs(money.majorPart)) + "." + String(repeating: "0", count: max(0, digits - fraction.count)) + fraction
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil { value = "'" + value }
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
