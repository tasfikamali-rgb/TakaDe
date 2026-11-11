import Foundation

/// How an expense total is divided among participants.
public enum SplitRule: Hashable, Codable, Sendable {
    /// Everyone listed pays the same; leftover poisha go to the first participants in order.
    case equal([MemberID])
    /// Each participant's exact amount. Must add up to the total.
    case exact([MemberID: Money])
    /// Percentages in basis points (10000 = 100%). Must add up to 10000.
    case percentage([MemberID: Int])
    /// Weighted shares, e.g. 2 shares for a couple, 1 for a single person.
    case shares([MemberID: Int])
    /// Equal, plus or minus a fixed amount per person: "+150 for the extra drink".
    /// Every key takes part; a zero means no adjustment. What's left after the
    /// adjustments is split equally, then each adjustment is added.
    case adjusted([MemberID: Money])
}

public enum SplitError: Error, Equatable, Sendable {
    case noParticipants
    case nonPositiveTotal
    case exactAmountsDoNotMatchTotal(expected: Money, actual: Money)
    case percentagesDoNotSumTo100(basisPoints: Int)
    case negativeOrZeroWeight(MemberID)
    case negativeAmount(MemberID)
    /// The extras add up to more than the total, so nothing is left to split.
    case adjustmentsExceedTotal(total: Money, adjustments: Money)
    case currencyMismatch
    case overflow
}

/// The result of splitting: who owes what share of the expense. Always sums exactly to the total.
public struct Allocation: Hashable, Codable, Sendable {
    public let shares: [MemberID: Money]
    public init(shares: [MemberID: Money]) { self.shares = shares }

    public func total(in currency: Currency) throws -> Money {
        try shares.values.sum(in: currency)
    }
}

public enum SplitCalculator {
    /// Splits `total` by `rule`. Rounding is deterministic: amounts are floored and the
    /// remaining minor units go one each to participants with the largest remainders,
    /// ties broken by the participant order given (or by MemberID for dictionaries).
    public static func allocate(_ total: Money, by rule: SplitRule) throws -> Allocation {
        guard total.minorUnits > 0 else { throw SplitError.nonPositiveTotal }

        switch rule {
        case .equal(let members):
            let unique = members.uniqued()
            guard !unique.isEmpty else { throw SplitError.noParticipants }
            return try weighted(total, weights: unique.map { ($0, 1) })

        case .exact(let amounts):
            guard !amounts.isEmpty else { throw SplitError.noParticipants }
            for (member, amount) in amounts {
                guard amount.currency == total.currency else { throw SplitError.currencyMismatch }
                guard amount.minorUnits >= 0 else { throw SplitError.negativeAmount(member) }
            }
            let sum: Money
            do { sum = try amounts.values.sum(in: total.currency) } catch { throw SplitError.overflow }
            guard sum == total else { throw SplitError.exactAmountsDoNotMatchTotal(expected: total, actual: sum) }
            return Allocation(shares: amounts)

        case .percentage(let basisPoints):
            guard !basisPoints.isEmpty else { throw SplitError.noParticipants }
            for (member, bp) in basisPoints where bp <= 0 { throw SplitError.negativeOrZeroWeight(member) }
            let sum = basisPoints.values.reduce(0, +)
            guard sum == 10_000 else { throw SplitError.percentagesDoNotSumTo100(basisPoints: sum) }
            return try weighted(total, weights: basisPoints.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })

        case .shares(let weights):
            guard !weights.isEmpty else { throw SplitError.noParticipants }
            for (member, w) in weights where w <= 0 { throw SplitError.negativeOrZeroWeight(member) }
            return try weighted(total, weights: weights.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })

        case .adjusted(let adjustments):
            guard !adjustments.isEmpty else { throw SplitError.noParticipants }
            guard adjustments.values.allSatisfy({ $0.currency == total.currency }) else { throw SplitError.currencyMismatch }
            let extra: Money
            do { extra = try adjustments.values.sum(in: total.currency) } catch { throw SplitError.overflow }
            let (rest, restOverflow) = total.minorUnits.subtractingReportingOverflow(extra.minorUnits)
            guard !restOverflow else { throw SplitError.overflow }
            guard rest >= 0 else { throw SplitError.adjustmentsExceedTotal(total: total, adjustments: extra) }
            let members = adjustments.keys.sorted()
            let base = try weighted(Money(minorUnits: rest, currency: total.currency), weights: members.map { ($0, 1) })
            var shares: [MemberID: Money] = [:]
            for member in members {
                let (amount, overflow) = base.shares[member, default: .zero(total.currency)].minorUnits
                    .addingReportingOverflow(adjustments[member, default: .zero(total.currency)].minorUnits)
                guard !overflow else { throw SplitError.overflow }
                guard amount >= 0 else { throw SplitError.negativeAmount(member) }
                shares[member] = Money(minorUnits: amount, currency: total.currency)
            }
            return Allocation(shares: shares)
        }
    }

    /// Largest-remainder method over integer weights.
    private static func weighted(_ total: Money, weights: [(MemberID, Int)]) throws -> Allocation {
        let weightSum = Int64(weights.reduce(0) { $0 + $1.1 })
        var floors: [(member: MemberID, amount: Int64, remainder: Int64, order: Int)] = []
        var allocated: Int64 = 0

        for (order, (member, weight)) in weights.enumerated() {
            let (product, overflow) = total.minorUnits.multipliedReportingOverflow(by: Int64(weight))
            guard !overflow else { throw SplitError.overflow }
            let amount = product / weightSum
            floors.append((member, amount, product % weightSum, order))
            allocated += amount
        }

        var leftover = total.minorUnits - allocated
        let priority = floors.indices.sorted {
            floors[$0].remainder != floors[$1].remainder
                ? floors[$0].remainder > floors[$1].remainder
                : floors[$0].order < floors[$1].order
        }
        var index = 0
        while leftover > 0 {
            floors[priority[index % priority.count]].amount += 1
            leftover -= 1
            index += 1
        }

        var shares: [MemberID: Money] = [:]
        for entry in floors { shares[entry.member] = Money(minorUnits: entry.amount, currency: total.currency) }
        return Allocation(shares: shares)
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
