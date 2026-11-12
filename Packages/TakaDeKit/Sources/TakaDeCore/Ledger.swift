import Foundation

/// A person in a group. On this device only; not an authenticated account.
/// `displayName` is stored and shown exactly as entered: never translated or normalized.
public struct Member: Hashable, Codable, Sendable, Identifiable {
    public let id: MemberID
    /// The person's own name. For "me" it's the account name, which can't be changed.
    public var displayName: String
    /// True for the person using this device.
    public var isMe: Bool
    /// What this group calls the person, if anyone set one. Only this group sees it, and it
    /// never changes `displayName`. Nil (or empty) means no nickname.
    public var nickname: String?

    public init(id: MemberID = MemberID(), displayName: String, isMe: Bool = false, nickname: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.isMe = isMe
        self.nickname = nickname
    }

    /// The nickname when there is one, otherwise the name.
    public var shownName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nickname }
        return displayName
    }
}

public struct ExpenseGroup: Hashable, Codable, Sendable, Identifiable {
    public let id: GroupID
    public var name: String
    public var currency: Currency
    public var members: [Member]
    public let createdAt: Date
    public var archivedAt: Date?
    /// On: suggest the fewest payments, combining debts across people. Off: each person
    /// pays the people they actually owe. On by default.
    public var simplifiesDebts: Bool
    /// A trip or flat (standard), or a mess with daily meal counts.
    public var kind: GroupKind
    /// Who keeps a mess's books: meals, bazar and deposits. Nil for standard groups.
    public var managerID: MemberID?
    /// The group's colour, taken from its photo, as "#RRGGBB". Screens turn it into a soft
    /// tint that stays readable in light and dark. Nil means the standard lilac.
    public var accentHex: String?
    /// Who made the group. Only they can delete it, for everyone (Sabit, 2026-11-12). Set
    /// once and never changed; nil for groups made before this was recorded.
    public var createdBy: MemberID?

    public init(id: GroupID = GroupID(), name: String, currency: Currency = .bdt, members: [Member], createdAt: Date = Date(), archivedAt: Date? = nil, simplifiesDebts: Bool = true, kind: GroupKind = .standard, managerID: MemberID? = nil, accentHex: String? = nil, createdBy: MemberID? = nil) {
        self.id = id
        self.name = name
        self.currency = currency
        self.members = members
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.simplifiesDebts = simplifiesDebts
        self.kind = kind
        self.managerID = managerID
        self.accentHex = accentHex
        self.createdBy = createdBy
    }

    public var isMess: Bool { kind == .mess }

    /// The person who can delete the group. Groups made before `createdBy` existed fall back
    /// to the first person listed: the app has always put the maker first, and every phone
    /// keeps the same order.
    public var ownerID: MemberID? { createdBy ?? members.first?.id }

    private enum CodingKeys: String, CodingKey {
        case id, name, currency, members, createdAt, archivedAt, simplifiesDebts, kind, managerID, accentHex, createdBy
    }

    /// Older snapshots have no `simplifiesDebts`; they decode with it on.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(GroupID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        currency = try c.decode(Currency.self, forKey: .currency)
        members = try c.decode([Member].self, forKey: .members)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        simplifiesDebts = try c.decodeIfPresent(Bool.self, forKey: .simplifiesDebts) ?? true
        kind = try c.decodeIfPresent(GroupKind.self, forKey: .kind) ?? .standard
        managerID = try c.decodeIfPresent(MemberID.self, forKey: .managerID)
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex)
        createdBy = try c.decodeIfPresent(MemberID.self, forKey: .createdBy)
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
    /// Optional; older expenses have none.
    public var category: ExpenseCategory?
    /// Incremented on each edit. Edits are recorded in the audit log.
    public var version: Int
    /// Soft delete. Deleted expenses stop affecting balances but stay in history.
    public var deletedAt: Date?
    /// When on, a copy is added each month on the same day, like rent or the internet bill.
    public var repeatsMonthly: Bool
    /// For a monthly copy: the expense it was copied from.
    public var repeatOf: ExpenseID?
    /// A photo of the receipt, kept as a file on the phone (and, in a shared group,
    /// encrypted on the relay). Nil when there's no photo.
    public var receiptID: UUID?
    /// Who made this version: the person in the group who added, edited or deleted it.
    /// Set by the repository on save, so a shared group's Activity can say who edited
    /// something on another phone. Nil for older saves and automatic monthly copies.
    public var changedBy: MemberID?

    public init(id: ExpenseID = ExpenseID(), groupID: GroupID, title: String, total: Money, paidBy: [MemberID: Money], splitRule: SplitRule, occurredAt: Date = Date(), note: String? = nil, category: ExpenseCategory? = nil, version: Int = 1, deletedAt: Date? = nil, repeatsMonthly: Bool = false, repeatOf: ExpenseID? = nil, receiptID: UUID? = nil) throws {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.total = total
        self.paidBy = paidBy
        self.splitRule = splitRule
        self.allocation = try SplitCalculator.allocate(total, by: splitRule)
        self.occurredAt = occurredAt
        self.note = note
        self.category = category
        self.version = version
        self.deletedAt = deletedAt
        self.repeatsMonthly = repeatsMonthly
        self.repeatOf = repeatOf
        self.receiptID = receiptID
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case id, groupID, title, total, paidBy, splitRule, allocation, occurredAt, note, category, version, deletedAt, repeatsMonthly, repeatOf, receiptID, changedBy
    }

    /// Expenses saved before monthly repeats decode as not repeating.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ExpenseID.self, forKey: .id)
        groupID = try c.decode(GroupID.self, forKey: .groupID)
        title = try c.decode(String.self, forKey: .title)
        total = try c.decode(Money.self, forKey: .total)
        paidBy = try c.decode([MemberID: Money].self, forKey: .paidBy)
        splitRule = try c.decode(SplitRule.self, forKey: .splitRule)
        allocation = try c.decode(Allocation.self, forKey: .allocation)
        occurredAt = try c.decode(Date.self, forKey: .occurredAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        category = try c.decodeIfPresent(ExpenseCategory.self, forKey: .category)
        version = try c.decode(Int.self, forKey: .version)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        repeatsMonthly = try c.decodeIfPresent(Bool.self, forKey: .repeatsMonthly) ?? false
        repeatOf = try c.decodeIfPresent(ExpenseID.self, forKey: .repeatOf)
        receiptID = try c.decodeIfPresent(UUID.self, forKey: .receiptID)
        changedBy = try c.decodeIfPresent(MemberID.self, forKey: .changedBy)
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
    /// The amount of a payment the provider confirmed, or that the person paid marked
    /// received, can only be changed by them (and a confirmed one not at all).
    case settlementAmountLocked
}
