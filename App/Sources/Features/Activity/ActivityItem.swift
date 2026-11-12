import Foundation
import TakaDeCore

/// One line in Activity or a group's History: who did what, and for an edit, what changed.
struct ActivityItem: Identifiable, Hashable {
    let id: UUID
    let group: ExpenseGroup
    let occurredAt: Date
    /// Who made the change, when known.
    let actor: MemberID?
    /// The person using this phone made it (shown on the right, like your own messages).
    let isMine: Bool
    /// It came from someone else's phone in a shared group.
    let isFromOthers: Bool
    /// "Rafi edited Dinner".
    let headline: String
    /// "Amount: ৳ 500.00 → ৳ 650.00", "Split changed"; empty when there's nothing to add.
    let details: [String]
    let amount: Money?
    /// A deleted expense or a reversed payment: shown struck through.
    let isRemoved: Bool
}
