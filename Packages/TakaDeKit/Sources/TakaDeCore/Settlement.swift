import Foundation

/// How a settlement was (or will be) paid. Payment rails are not integrated yet;
/// see docs/decisions-needed.md. Nothing here moves money.
public enum SettlementMethod: String, Codable, Sendable, CaseIterable {
    case cash
    case bkash
    case nagad
    case rocket
    case upay
    case bankTransfer
    case other
}

/// Lifecycle of a settlement. Only trusted provider evidence may move a settlement
/// to `.confirmed`; there is no such evidence source in the local-only MVP, so the
/// app can only ever reach `.reportedUnverified` today.
public enum SettlementStatus: String, Codable, Sendable, CaseIterable {
    case notStarted = "not_started"
    case handoffStarted = "handoff_started"
    case pending
    case reportedUnverified = "reported_unverified"
    /// The person who was owed marked it received (e.g. cash in hand). Clears the debt,
    /// but is the recipient's word, never provider verification.
    case acknowledgedByRecipient = "acknowledged_by_recipient"
    case confirmed
    case failed
    case reversed

    /// Where a status may move to, and whether that move needs provider evidence.
    public func canTransition(to next: SettlementStatus, withProviderEvidence: Bool) -> Bool {
        switch (self, next) {
        case (.notStarted, .handoffStarted), (.notStarted, .reportedUnverified),
             (.handoffStarted, .pending), (.handoffStarted, .reportedUnverified), (.handoffStarted, .failed),
             (.pending, .reportedUnverified), (.pending, .failed):
            return true
        case (.pending, .confirmed), (.reportedUnverified, .confirmed),
             (.confirmed, .reversed):
            return withProviderEvidence
        case (.notStarted, .acknowledgedByRecipient), (.handoffStarted, .acknowledgedByRecipient),
             (.pending, .acknowledgedByRecipient), (.reportedUnverified, .acknowledgedByRecipient):
            // Only callable through Settlement.acknowledge(by:), which checks the recipient.
            return true
        case (.reportedUnverified, .reversed), (.acknowledgedByRecipient, .reversed):
            // Withdrawing a report or acknowledgement made by mistake.
            return true
        default:
            return false
        }
    }

    /// Whether this settlement should reduce what people owe in the displayed balance.
    /// Unverified reports count, but the UI must label them as reported, not verified.
    public var countsTowardBalance: Bool {
        self == .reportedUnverified || self == .acknowledgedByRecipient || self == .confirmed
    }
}

/// A transfer from one member to another that reduces a debt.
public struct Settlement: Hashable, Codable, Sendable, Identifiable {
    public let id: SettlementID
    public let groupID: GroupID
    public let from: MemberID
    public let to: MemberID
    public private(set) var amount: Money
    public var method: SettlementMethod
    public private(set) var status: SettlementStatus
    /// A provider transaction reference typed by the user. Untrusted; never proof of payment.
    public var userReference: String?
    public let createdAt: Date
    public private(set) var updatedAt: Date
    /// Who made this version (recorded, edited or changed its status). Set by the
    /// repository on save, so Activity can say who edited a payment. Nil for older saves.
    public var changedBy: MemberID?

    public init(id: SettlementID = SettlementID(), groupID: GroupID, from: MemberID, to: MemberID, amount: Money, method: SettlementMethod, status: SettlementStatus = .notStarted, userReference: String? = nil, createdAt: Date = Date()) throws {
        guard from != to else { throw LedgerError.settlementToSelf }
        guard amount.minorUnits > 0 else { throw LedgerError.nonPositiveSettlement }
        self.id = id
        self.groupID = groupID
        self.from = from
        self.to = to
        self.amount = amount
        self.method = method
        self.status = status
        self.userReference = userReference
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Marks the settlement as received. Only the recipient may do this.
    public mutating func acknowledge(by member: MemberID, at date: Date = Date()) throws {
        guard member == to else { throw LedgerError.onlyRecipientCanAcknowledge }
        guard status.canTransition(to: .acknowledgedByRecipient, withProviderEvidence: false) else {
            throw LedgerError.illegalStatusTransition(from: status, to: .acknowledgedByRecipient)
        }
        status = .acknowledgedByRecipient
        updatedAt = date
    }

    /// Fixes a payment recorded with the wrong amount, method or transaction id. The people
    /// and the status stay. Once the person paid has marked it received, only they can
    /// change the amount; a provider-confirmed amount never changes.
    public mutating func edit(amount newAmount: Money, method newMethod: SettlementMethod, userReference newReference: String?,
                              by member: MemberID?, at date: Date = Date()) throws {
        guard newAmount.minorUnits > 0 else { throw LedgerError.nonPositiveSettlement }
        guard newAmount.currency == amount.currency else { throw LedgerError.invalidPayment }
        if newAmount != amount, !Self.canChangeAmount(status: status, to: to, by: member) {
            throw LedgerError.settlementAmountLocked
        }
        amount = newAmount
        method = newMethod
        userReference = newReference
        updatedAt = date
    }

    /// Whether `member` may change the amount of a payment in `status` made to `recipient`.
    public static func canChangeAmount(status: SettlementStatus, to recipient: MemberID, by member: MemberID?) -> Bool {
        switch status {
        case .confirmed, .reversed: return false
        case .acknowledgedByRecipient: return member == recipient
        default: return true
        }
    }

    public mutating func transition(to next: SettlementStatus, withProviderEvidence: Bool = false, at date: Date = Date()) throws {
        guard next != .acknowledgedByRecipient else { throw LedgerError.onlyRecipientCanAcknowledge }
        guard status.canTransition(to: next, withProviderEvidence: withProviderEvidence) else {
            throw LedgerError.illegalStatusTransition(from: status, to: next)
        }
        status = next
        updatedAt = date
    }
}

public extension Settlement {
    /// A transaction id compared without case, spaces or dashes, so "8N7A 6b5c-4D" and
    /// "8N7A6B5C4D" match. Nil when empty.
    static func normalizedReference(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.uppercased().filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// An earlier settlement in the list with the same transaction id, ignoring ones that
    /// failed or were reversed. One bKash TrxID can only pay one debt, so a match usually
    /// means the same payment is being recorded twice. This only catches typing the same
    /// id twice; it doesn't verify anything with the provider.
    static func duplicate(ofReference reference: String?, in settlements: [Settlement]) -> Settlement? {
        guard let wanted = normalizedReference(reference) else { return nil }
        return settlements.first { other in
            other.status != .failed && other.status != .reversed
                && normalizedReference(other.userReference) == wanted
        }
    }
}
