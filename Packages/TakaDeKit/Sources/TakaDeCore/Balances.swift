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
    /// Who owes whom directly, from each expense's payers and shares, without combining
    /// debts across people. Used when a group turns "Simplify debts" off.
    public let directTransfers: [SuggestedTransfer]

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
            currency: currency,
            directTransfers: try directTransfers(currency: currency, expenses: expenses, settlements: settlements)
        )
    }

    /// The transfers to show: fewest payments when `simplify` is on, otherwise each
    /// person pays the people they actually owe.
    public static func transfers(_ balances: GroupBalances, simplify: Bool) -> [SuggestedTransfer] {
        simplify ? suggestedTransfers(balances) : balances.directTransfers
    }

    /// Pairwise debts. Each person's share of an expense is owed to its payers in
    /// proportion to what each paid (largest-remainder rounding, so nothing is lost);
    /// counted settlements reduce the debt between those two people. Debts in both
    /// directions between a pair cancel out.
    static func directTransfers(currency: Currency, expenses: [Expense], settlements: [Settlement]) throws -> [SuggestedTransfer] {
        struct Pair: Hashable { let from: MemberID; let to: MemberID }
        var owed: [Pair: Int64] = [:]

        func add(_ from: MemberID, _ to: MemberID, _ amount: Int64) throws {
            guard from != to, amount != 0 else { return }
            let (value, overflow) = owed[Pair(from: from, to: to), default: 0].addingReportingOverflow(amount)
            guard !overflow else { throw MoneyError.overflow }
            owed[Pair(from: from, to: to)] = value
        }

        for expense in expenses where expense.deletedAt == nil {
            let payers = expense.paidBy.filter { $0.value.minorUnits > 0 }
            guard !payers.isEmpty else { continue }
            if payers.count == 1, let payer = payers.keys.first {
                for (member, share) in expense.allocation.shares { try add(member, payer, share.minorUnits) }
                continue
            }
            // Several payers: give each payer but the last their exact amount, spread over
            // the participants by share; the last payer takes what's left of each share. Rows
            // add up to each share and columns to each payment, so nothing is lost to rounding.
            let shares = expense.allocation.shares.filter { $0.value.minorUnits > 0 }
            guard !shares.isEmpty else { continue }
            let weights = Dictionary(uniqueKeysWithValues: shares.map { ($0.key, Int($0.value.minorUnits)) })
            let orderedPayers = payers.keys.sorted()
            var assigned: [MemberID: Int64] = [:]
            for payer in orderedPayers.dropLast() {
                let parts = try SplitCalculator.allocate(payers[payer]!, by: .shares(weights))
                for (member, part) in parts.shares {
                    try add(member, payer, part.minorUnits)
                    assigned[member, default: 0] += part.minorUnits
                }
            }
            let last = orderedPayers.last!
            for (member, share) in shares {
                try add(member, last, share.minorUnits - assigned[member, default: 0])
            }
        }

        for settlement in settlements where settlement.status.countsTowardBalance {
            try add(settlement.from, settlement.to, -settlement.amount.minorUnits)
        }

        var transfers: [SuggestedTransfer] = []
        let pairs = Set(owed.keys.map { $0.from < $0.to ? Pair(from: $0.from, to: $0.to) : Pair(from: $0.to, to: $0.from) })
        for pair in pairs {
            let forward = owed[pair, default: 0]
            let backward = owed[Pair(from: pair.to, to: pair.from), default: 0]
            let (net, overflow) = forward.subtractingReportingOverflow(backward)
            guard !overflow else { throw MoneyError.overflow }
            if net > 0 {
                transfers.append(SuggestedTransfer(from: pair.from, to: pair.to, amount: Money(minorUnits: net, currency: currency)))
            } else if net < 0 {
                transfers.append(SuggestedTransfer(from: pair.to, to: pair.from, amount: Money(minorUnits: -net, currency: currency)))
            }
        }
        return transfers.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : ($0.from != $1.from ? $0.from < $1.from : $0.to < $1.to) }
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
