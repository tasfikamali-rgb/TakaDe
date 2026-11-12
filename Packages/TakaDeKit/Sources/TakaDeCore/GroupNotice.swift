import Foundation

/// What to tell the person using this phone after other people changed a shared group
/// (docs/adr/0025-group-change-notifications.md). Worked out on the phone, after the
/// changes are decrypted, so names and amounts never pass through the relay in the clear.
///
/// Only changes this person is part of count: an expense they paid for or have a share in,
/// or a payment to or from them. Nothing is said when the phone doesn't know which person
/// it is yet, because "you" would be a guess.
public struct GroupNotice: Hashable, Sendable {
    public enum Event: Hashable, Sendable {
        /// Someone added, edited, deleted or restored an expense. `myShare` is this person's
        /// part of it, nil when they have none or it was deleted.
        case expense(title: String, action: AuditEvent.Action, by: MemberID?, myShare: Money?)
        /// Someone recorded paying this person. Their word, not proof of payment.
        case paidYou(by: MemberID, amount: Money)
        /// The person this phone's owner paid marked it received.
        case markedReceived(by: MemberID, amount: Money)
        /// Any other change to a payment this person is in (edited, withdrawn).
        case paymentChanged(by: MemberID?, amount: Money)
    }

    public let groupID: GroupID
    public let events: [Event]
    /// Where this person stands in the group after the changes. Positive: they're owed.
    public let myBalance: Money?

    public init(groupID: GroupID, events: [Event], myBalance: Money?) {
        self.groupID = groupID
        self.events = events
        self.myBalance = myBalance
    }

    /// The notice for a batch of changes from other phones, or nil when none involve this
    /// person. `group` is the group after the changes, with this phone's "me" marked.
    public static func make(group: ExpenseGroup, changes: [AppliedChange], myBalance: Money?) -> GroupNotice? {
        guard let me = group.members.first(where: \.isMe)?.id else { return nil }
        let events = changes.compactMap { event(for: $0, me: me) }
        guard !events.isEmpty else { return nil }
        return GroupNotice(groupID: group.id, events: events, myBalance: myBalance)
    }

    static func event(for change: AppliedChange, me: MemberID) -> Event? {
        switch change.item {
        case .expense(let expense):
            // Made on another phone by the same person: nothing new for them.
            if expense.changedBy == me { return nil }
            let share = expense.allocation.shares[me].flatMap { $0.minorUnits > 0 ? $0 : nil }
            let paid = expense.paidBy[me].map { $0.minorUnits > 0 } ?? false
            guard share != nil || paid else { return nil }
            let shown = expense.deletedAt == nil ? share : nil
            return .expense(title: expense.title, action: change.action, by: expense.changedBy, myShare: shown)

        case .settlement(let settlement):
            guard settlement.from == me || settlement.to == me else { return nil }
            let other = settlement.from == me ? settlement.to : settlement.from
            let actor = settlement.changedBy ?? other
            if actor == me { return nil }
            let open: Set<SettlementStatus> = [.notStarted, .handoffStarted, .pending, .reportedUnverified]
            if change.action == .created, settlement.to == me, open.contains(settlement.status) {
                return .paidYou(by: settlement.from, amount: settlement.amount)
            }
            if settlement.status == .acknowledgedByRecipient, settlement.from == me, change.action != .edited {
                return .markedReceived(by: settlement.to, amount: settlement.amount)
            }
            return .paymentChanged(by: settlement.changedBy, amount: settlement.amount)
        }
    }
}
