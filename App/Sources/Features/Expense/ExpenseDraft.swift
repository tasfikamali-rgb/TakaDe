import Foundation
import Observation
import TakaDeCore

/// Everything typed into the add-expense form, and the rules for turning it into an
/// `Expense`. Kept out of the view so it can be tested and reused.
@MainActor
@Observable
final class ExpenseDraft {
    let group: ExpenseGroup
    /// The expense being edited, or nil for a new one.
    let original: Expense?
    var title = ""
    /// What's on the keypad, e.g. "1200÷4".
    var amountExpression = ""
    var occurredAt = Date()
    var payer: MemberID
    /// When on, each person types what they paid instead of one payer paying it all.
    var severalPayers = false
    private var paidText: [MemberID: String] = [:]
    var method: SplitMethod = .equal
    var included: Set<MemberID>
    private var exactText: [MemberID: String] = [:]
    private var percentText: [MemberID: String] = [:]
    private var shareCounts: [MemberID: Int] = [:]
    private var adjustText: [MemberID: String] = [:]

    init(group: ExpenseGroup) {
        self.group = group
        original = nil
        payer = group.me?.id ?? group.members[0].id
        included = Set(group.members.map(\.id))
    }

    /// Starts from a saved expense, so editing shows exactly what was recorded.
    init(editing expense: Expense, in group: ExpenseGroup) {
        self.group = group
        original = expense
        title = expense.title
        amountExpression = KeypadText.plain(expense.total)
        occurredAt = expense.occurredAt
        payer = expense.paidBy.keys.sorted().first ?? group.me?.id ?? group.members[0].id
        if expense.paidBy.count > 1 {
            severalPayers = true
            paidText = expense.paidBy.mapValues(KeypadText.plain)
        }
        included = Set(group.members.map(\.id))
        switch expense.splitRule {
        case .equal(let members):
            method = .equal
            included = Set(members)
        case .exact(let amounts):
            method = .exact
            exactText = amounts.mapValues(KeypadText.plain)
        case .percentage(let basisPoints):
            method = .percentage
            let percent = Currency(code: "PCT", minorUnitDigits: 2)
            percentText = basisPoints.mapValues { KeypadText.plain(Money(minorUnits: Int64($0), currency: percent)) }
        case .shares(let weights):
            method = .shares
            shareCounts = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, weights[$0.id, default: 0]) })
        case .adjusted(let adjustments):
            method = .adjusted
            included = Set(adjustments.keys)
            adjustText = adjustments.filter { !$0.value.isZero }.mapValues(Self.signedText)
        }
    }

    var isEditing: Bool { original != nil }

    subscript(exactFor id: MemberID) -> String {
        get { exactText[id, default: ""] }
        set { exactText[id] = newValue }
    }

    subscript(percentFor id: MemberID) -> String {
        get { percentText[id, default: ""] }
        set { percentText[id] = newValue }
    }

    subscript(sharesFor id: MemberID) -> Int {
        get { shareCounts[id, default: 1] }
        set { shareCounts[id] = newValue }
    }

    subscript(paidFor id: MemberID) -> String {
        get { paidText[id, default: ""] }
        set { paidText[id] = newValue }
    }

    /// Who paid and how much. Nil while an amount can't be read.
    var paidBy: [MemberID: Money]? {
        guard let total else { return nil }
        guard severalPayers else { return [payer: total] }
        var result: [MemberID: Money] = [:]
        for member in group.members {
            let text = paidText[member.id, default: ""].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard let value = try? Money.parse(text, currency: group.currency), !value.isNegative else { return nil }
            if !value.isZero { result[member.id] = value }
        }
        return result.isEmpty ? nil : result
    }

    /// With several payers: how much of the total nobody has paid yet (negative when
    /// they've typed more than the total). Nil when it adds up or can't be read.
    var unpaid: Money? {
        guard severalPayers, let total else { return nil }
        guard let paidBy else { return paidText.values.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) ? total : nil }
        let paid = paidBy.values.reduce(Int64(0)) { $0 + $1.minorUnits }
        let left = total.minorUnits - paid
        return left == 0 ? nil : Money(minorUnits: left, currency: total.currency)
    }

    /// "+150" or "-60": the extra (or less) this person pays on top of an equal part.
    subscript(adjustFor id: MemberID) -> String {
        get { adjustText[id, default: ""] }
        set { adjustText[id] = newValue }
    }

    subscript(includes id: MemberID) -> Bool {
        get { included.contains(id) }
        set { if newValue { included.insert(id) } else { included.remove(id) } }
    }

    var total: Money? { try? AmountExpression.evaluate(amountExpression, currency: group.currency) }

    var rule: SplitRule? {
        switch method {
        case .equal:
            let members = group.members.map(\.id).filter(included.contains)
            return members.isEmpty ? nil : .equal(members)
        case .exact:
            var amounts: [MemberID: Money] = [:]
            for member in group.members {
                let text = exactText[member.id, default: ""]
                guard !text.isEmpty else { continue }
                guard let value = try? Money.parse(text, currency: group.currency) else { return nil }
                amounts[member.id] = value
            }
            return amounts.isEmpty ? nil : .exact(amounts)
        case .percentage:
            var basisPoints: [MemberID: Int] = [:]
            for member in group.members {
                let text = percentText[member.id, default: ""]
                guard !text.isEmpty else { continue }
                // Percent with up to two decimals, as basis points (12.5% -> 1250).
                guard let value = try? Money.parse(text, currency: Currency(code: "PCT", minorUnitDigits: 2)), value.minorUnits > 0 else { return nil }
                basisPoints[member.id] = Int(value.minorUnits)
            }
            return basisPoints.isEmpty ? nil : .percentage(basisPoints)
        case .shares:
            let weights = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, shareCounts[$0.id, default: 1]) }).filter { $0.value > 0 }
            return weights.isEmpty ? nil : .shares(weights)
        case .adjusted:
            var adjustments: [MemberID: Money] = [:]
            for member in group.members where included.contains(member.id) {
                var text = adjustText[member.id, default: ""].trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("+") { text.removeFirst() }
                if text.isEmpty || text == "-" {
                    adjustments[member.id] = .zero(group.currency)
                    continue
                }
                guard let value = try? Money.parse(text, currency: group.currency) else { return nil }
                adjustments[member.id] = value
            }
            return adjustments.isEmpty ? nil : .adjusted(adjustments)
        }
    }

    private static func signedText(_ money: Money) -> String {
        money.isNegative ? "-" + KeypadText.plain(money.magnitude) : "+" + KeypadText.plain(money)
    }

    var preview: Result<Allocation, SplitError>? {
        guard let total, let rule else { return nil }
        do {
            return .success(try SplitCalculator.allocate(total, by: rule))
        } catch let error as SplitError {
            return .failure(error)
        } catch {
            return .failure(.overflow)
        }
    }

    func share(for id: MemberID) -> Money? {
        guard case .success(let allocation) = preview else { return nil }
        return allocation.shares[id]
    }

    /// True when an equal split can't divide evenly, so a few people pay one poisha more.
    var hasRoundingRemainder: Bool {
        guard method == .equal, let total, !included.isEmpty else { return false }
        return total.minorUnits % Int64(included.count) != 0
    }

    /// True once anything has been typed (or, when editing, always), so a swipe-down doesn't throw it away.
    var hasContent: Bool {
        isEditing || !trimmedTitle.isEmpty || !amountExpression.isEmpty
    }

    var canSave: Bool {
        guard !trimmedTitle.isEmpty, case .success = preview, paidBy != nil, unpaid == nil else { return false }
        return true
    }

    func makeExpense() throws -> Expense {
        guard let total, let rule else { throw SplitError.noParticipants }
        guard let paidBy else { throw LedgerError.noPayer }
        if let original {
            // Same id and a new version, so history shows an edit rather than a new expense.
            return try Expense(id: original.id, groupID: group.id, title: trimmedTitle, total: total, paidBy: paidBy,
                               splitRule: rule, occurredAt: occurredAt, note: original.note, version: original.version + 1)
        }
        return try Expense(groupID: group.id, title: trimmedTitle, total: total, paidBy: paidBy, splitRule: rule, occurredAt: occurredAt)
    }

    /// Fills in fields from a reviewed receipt suggestion.
    func apply(merchant: String?, total: Money?, date: Date?) {
        if let merchant, trimmedTitle.isEmpty { title = merchant }
        if let total { amountExpression = KeypadText.plain(total) }
        if let date { occurredAt = date }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}
