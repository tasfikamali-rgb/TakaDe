import Foundation

/// A payment request or a request for proof, sent to a friend in a TakaDe chat
/// (docs/adr/0031-payment-asks-in-chat.md). It rides inside the sealed chat envelope, so the
/// server sees neither the group, the amount nor the numbers. It points at a group on both
/// phones; it never moves money and never marks anything paid.
public struct PaymentAsk: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// "Please pay me": the person paid asks the person who owes.
        case pay
        /// "Please send proof": the person paid asks the payer for the transaction ID of a
        /// payment the payer recorded but the person paid hasn't confirmed.
        case proof
    }

    /// A wallet number or bank details the asker wants to be paid to, sent so the payer can
    /// copy it even when their phone has no number saved for the asker.
    public struct Handle: Codable, Hashable, Sendable {
        public var rail: PaymentHandle.Rail
        public var handle: String

        public init(rail: PaymentHandle.Rail, handle: String) {
            self.rail = rail
            self.handle = handle
        }
    }

    public var kind: Kind
    public var groupID: GroupID
    /// The group's name when it was sent, for a phone that doesn't have the group.
    public var groupName: String
    /// Who pays (the person the ask goes to).
    public var from: MemberID
    /// Who is paid (the person asking).
    public var to: MemberID
    public var amount: Money
    /// For `.proof`: the payment the payer recorded.
    public var settlementID: SettlementID?
    public var handles: [Handle]

    public static let maxHandles = 6
    public static let maxGroupName = 80

    public init(kind: Kind, groupID: GroupID, groupName: String, from: MemberID, to: MemberID, amount: Money,
                settlementID: SettlementID? = nil, handles: [Handle] = []) {
        self.kind = kind
        self.groupID = groupID
        self.groupName = groupName
        self.from = from
        self.to = to
        self.amount = amount
        self.settlementID = settlementID
        self.handles = handles
    }

    /// The ask as it may be shown: a positive amount, two different people, a proof ask that
    /// names its payment, and only handles that pass the same checks as saved numbers. Nil
    /// when it doesn't make sense, so a damaged or odd message shows as plain text instead.
    public func validated() -> PaymentAsk? {
        guard amount.minorUnits > 0, from != to, kind != .proof || settlementID != nil else { return nil }
        var copy = self
        copy.groupName = String(groupName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxGroupName))
        copy.handles = handles.prefix(Self.maxHandles).compactMap { handle in
            guard let checked = try? PaymentHandle(memberID: to, rail: handle.rail, handle: handle.handle) else { return nil }
            return Handle(rail: checked.rail, handle: checked.handle)
        }
        return copy
    }

    /// Where the ask stands, worked out on each phone from the group's own payments; nothing
    /// extra is sent. A pay ask is answered by any payment from the payer to the asker
    /// recorded after it was sent; a proof ask by its payment getting a transaction ID or
    /// being marked received.
    public enum Progress: Equatable, Sendable {
        case waiting
        /// The payer recorded paying; the person paid hasn't confirmed.
        case reportedPaid
        /// The person paid marked it received.
        case received
        /// The payer added a transaction ID (proof asks).
        case reference(String)
        /// The payment was withdrawn.
        case withdrawn
    }

    public func progress(sentAt: Date, in settlements: [Settlement]) -> Progress {
        switch kind {
        case .pay:
            let answers = settlements.filter {
                $0.from == from && $0.to == to && $0.createdAt >= sentAt.addingTimeInterval(-60) && $0.status.countsTowardBalance
            }
            if answers.contains(where: { $0.status == .acknowledgedByRecipient || $0.status == .confirmed }) { return .received }
            return answers.isEmpty ? .waiting : .reportedPaid
        case .proof:
            guard let settlement = settlements.first(where: { $0.id == settlementID }) else { return .waiting }
            switch settlement.status {
            case .reversed, .failed: return .withdrawn
            case .acknowledgedByRecipient, .confirmed: return .received
            default:
                if let reference = settlement.userReference?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty {
                    return .reference(reference)
                }
                return .waiting
            }
        }
    }
}
