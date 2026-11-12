import Foundation
import TakaDeCore

/// One line in Activity or a group's History: who did what, and for an edit, what changed.
struct ActivityItem: Identifiable, Hashable {
    let id: UUID
    let group: ExpenseGroup
    let occurredAt: Date
    /// "Rafi edited Dinner".
    let headline: String
    /// "Amount: ৳ 500.00 → ৳ 650.00", "Split changed"; empty when there's nothing to add.
    let details: [String]
    let amount: Money?
    /// A deleted expense or a reversed payment: shown struck through.
    let isRemoved: Bool
}
