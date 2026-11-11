import Foundation

/// A suggested transfer that would settle part of the group's debts.
public struct SuggestedTransfer: Hashable, Sendable {
    public let from: MemberID
    public let to: MemberID
    public let amount: Money
}

public struct GroupBalances: Sendable {
    /// Positive: the member is owed money. Negative: the member owes money.
    public let net: [MemberID: Money]
    /// Portion of `net` movement that comes from unverified (user-reported) settlements,
    /// so the UI can say "includes ৳ x reported, not verified".
    public let unverifiedSettled: [MemberID: Money]
    public let currency: Currency

    public func net(for member: MemberID) -> Money { net[member] ?? .zero(currency) }
}

public enum BalanceCalculator {
    /// Derives balances from source entries. Deleted expenses and settlements that do not
    /// count toward balance are ignored. The result always sums to zero.
    public static func balances(members: [MemberID], currency: Currency, expenses: [Expense], settlements: [Settlement]) throws -> GroupBalances {
        var net: [MemberID: Int64] = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        var unverified: [MemberID: Int64] = [:]

        func add(_ member: MemberID, _ amount: Int64) throws {
            guard net[member] != nil else { throw LedgerError.unknownMember(member) }
            let (value, overflow) = net[member]!.addingReportingOverflow(amount)
            guard !overflow else { throw MoneyError.overflow }
            net[member] = value
        }

        for expense in expenses where expense.deletedAt == nil {
            guard expense.total.currency == currency else { throw MoneyError.currencyMismatch(currency, expense.total.currency) }
            for (member, paid) in expense.paidBy { try add(member, paid.minorUnits) }
            for (member, owed) in expense.allocation.shares { try add(member, -owed.minorUnits) }
        }

        for settlement in settlements where settlement.status.countsTowardBalance {
            guard settlement.amount.currency == currency else { throw MoneyError.currencyMismatch(currency, settlement.amount.currency) }
            try add(settlement.from, settlement.amount.minorUnits)
            try add(settlement.to, -settlement.amount.minorUnits)
            if settlement.status == .reportedUnverified {
                unverified[settlement.from, default: 0] += settlement.amount.minorUnits
                unverified[settlement.to, default: 0] += settlement.amount.minorUnits
            }
        }

        precondition(net.values.reduce(0, +) == 0, "Ledger invariant violated: balances do not sum to zero")
        return GroupBalances(
            net: net.mapValues { Money(minorUnits: $0, currency: currency) },
            unverifiedSettled: unverified.mapValues { Money(minorUnits: $0, currency: currency) },
            currency: currency
        )
    }

    /// Greedy simplification: repeatedly match the largest debtor with the largest creditor.
    /// Produces at most n-1 transfers. Deterministic for equal amounts (ties by MemberID).
    public static func suggestedTransfers(_ balances: GroupBalances) -> [SuggestedTransfer] {
        var debtors = balances.net.filter { $0.value.minorUnits < 0 }.map { ($0.key, -$0.value.minorUnits) }
        var creditors = balances.net.filter { $0.value.minorUnits > 0 }.map { ($0.key, $0.value.minorUnits) }
        var transfers: [SuggestedTransfer] = []

        let order: ((MemberID, Int64), (MemberID, Int64)) -> Bool = { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        while !debtors.isEmpty && !creditors.isEmpty {
            debtors.sort(by: order)
            creditors.sort(by: order)
            let amount = min(debtors[0].1, creditors[0].1)
            transfers.append(SuggestedTransfer(from: debtors[0].0, to: creditors[0].0, amount: Money(minorUnits: amount, currency: balances.currency)))
            debtors[0].1 -= amount
            creditors[0].1 -= amount
            if debtors[0].1 == 0 { debtors.removeFirst() }
            if creditors[0].1 == 0 { creditors.removeFirst() }
        }
        return transfers
    }
}
