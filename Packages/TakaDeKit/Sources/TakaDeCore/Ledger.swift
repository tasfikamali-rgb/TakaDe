import Foundation

/// A person in a group. On this device only; not an authenticated account.
/// `displayName` is stored and shown exactly as entered: never translated or normalized.
public struct Member: Hashable, Codable, Sendable, Identifiable {
    public let id: MemberID
    public var displayName: String
    /// True for the person using this device.
    public var isMe: Bool

    public init(id: MemberID = MemberID(), displayName: String, isMe: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isMe = isMe
    }
}

public struct ExpenseGroup: Hashable, Codable, Sendable, Identifiable {
    public let id: GroupID
    public var name: String
    public var currency: Currency
    public var members: [Member]
    public let createdAt: Date
    public var archivedAt: Date?

    public init(id: GroupID = GroupID(), name: String, currency: Currency = .bdt, members: [Member], createdAt: Date = Date(), archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.currency = currency
        self.members = members
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

/// A shared cost. Recording an expense is a claim, not a payment.
public struct Expense: Hashable, Codable, Sendable, Identifiable {
    public let id: ExpenseID
    public let groupID: GroupID
    public var title: String
    public var total: Money
    /// Who paid and how much. Must sum to `total`.
    public var paidBy: [MemberID: Money]
    /// The rule the user chose, kept so an edit can show the original intent.
    public var splitRule: SplitRule
    /// The computed shares. Must sum to `total`.
    public var allocation: Allocation
    public var occurredAt: Date
    public var note: String?
    /// Incremented on each edit. Edits are recorded in the audit log.
    public var version: Int
    /// Soft delete. Deleted expenses stop affecting balances but stay in history.
    public var deletedAt: Date?

    public init(id: ExpenseID = ExpenseID(), groupID: GroupID, title: String, total: Money, paidBy: [MemberID: Money], splitRule: SplitRule, occurredAt: Date = Date(), note: String? = nil, version: Int = 1, deletedAt: Date? = nil) throws {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.total = total
        self.paidBy = paidBy
        self.splitRule = splitRule
        self.allocation = try SplitCalculator.allocate(total, by: splitRule)
        self.occurredAt = occurredAt
        self.note = note
        self.version = version
        self.deletedAt = deletedAt
        try validate()
    }

    public func validate() throws {
        guard !paidBy.isEmpty else { throw LedgerError.noPayer }
        for (_, amount) in paidBy where amount.minorUnits < 0 || amount.currency != total.currency {
            throw LedgerError.invalidPayment
        }
        let paid = try paidBy.values.sum(in: total.currency)
        guard paid == total else { throw LedgerError.paymentsDoNotMatchTotal(expected: total, actual: paid) }
        guard try allocation.total(in: total.currency) == total else { throw LedgerError.allocationDoesNotMatchTotal }
    }
}

public enum LedgerError: Error, Equatable, Sendable {
    case noPayer
    case invalidPayment
    case paymentsDoNotMatchTotal(expected: Money, actual: Money)
    case allocationDoesNotMatchTotal
    case unknownMember(MemberID)
    case settlementToSelf
    case nonPositiveSettlement
    case illegalStatusTransition(from: SettlementStatus, to: SettlementStatus)
    case onlyRecipientCanAcknowledge
}
