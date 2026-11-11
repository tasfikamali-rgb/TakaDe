import Foundation

/// What gets shared when someone sends a group's balances to a chat. Contains only the
/// group name, member names and who pays whom: no expense titles, notes or history.
public struct GroupSummary: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let from: String
        public let to: String
        public let amount: Money
    }

    public let groupName: String
    public let lines: [Line]
    public let currency: Currency

    public init(group: ExpenseGroup, balances: GroupBalances) {
        groupName = group.name
        currency = group.currency
        let names = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, $0.displayName) })
        lines = BalanceCalculator.transfers(balances, simplify: group.simplifiesDebts).map {
            Line(from: names[$0.from] ?? "?", to: names[$0.to] ?? "?", amount: $0.amount)
        }
    }

    public var isSettled: Bool { lines.isEmpty }
}
