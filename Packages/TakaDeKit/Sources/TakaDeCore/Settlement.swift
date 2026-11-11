import Foundation

/// How a settlement was (or will be) paid. Payment rails are not integrated yet;
/// see docs/decisions-needed.md. Nothing here moves money.
public enum SettlementMethod: String, Codable, Sendable, CaseIterable {
    case cash
    case bkash
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
    public let amount: Money
    public var method: SettlementMethod
    public private(set) var status: SettlementStatus
    /// A provider transaction reference typed by the user. Untrusted; never proof of payment.
    public var userReference: String?
    public let createdAt: Date
    public private(set) var updatedAt: Date

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

    public mutating func transition(to next: SettlementStatus, withProviderEvidence: Bool = false, at date: Date = Date()) throws {
        guard next != .acknowledgedByRecipient else { throw LedgerError.onlyRecipientCanAcknowledge }
        guard status.canTransition(to: next, withProviderEvidence: withProviderEvidence) else {
            throw LedgerError.illegalStatusTransition(from: status, to: next)
        }
        status = next
        updatedAt = date
    }
}
