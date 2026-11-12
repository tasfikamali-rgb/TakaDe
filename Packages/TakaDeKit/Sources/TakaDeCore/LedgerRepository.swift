import Foundation

/// The storage boundary. UI and view models talk to this, never to SQL.
public protocol LedgerRepository: Sendable {
    func groups() async throws -> [ExpenseGroup]
    func group(_ id: GroupID) async throws -> ExpenseGroup?
    func save(_ group: ExpenseGroup, actor: MemberID?) async throws
    /// Takes someone out of a group. Only allowed while nothing in the group mentions them
    /// (no expense, deleted ones included, no payment, no meal count) and they aren't "me"
    /// or the mess manager; otherwise throws `MemberRemovalError` and changes nothing.
    func removeMember(_ member: MemberID, from group: GroupID, actor: MemberID?) async throws

    func expenses(in group: GroupID, includeDeleted: Bool) async throws -> [Expense]
    func save(_ expense: Expense, actor: MemberID?) async throws
    func delete(_ expense: ExpenseID, actor: MemberID?) async throws

    func settlements(in group: GroupID) async throws -> [Settlement]
    func save(_ settlement: Settlement, actor: MemberID?) async throws

    func history(of group: GroupID) async throws -> [AuditEvent]
}

/// Daily meal counts for mess groups.
public protocol MessRepository: Sendable {
    func mealCounts(in group: GroupID, month: MessMonth) async throws -> [MealCount]
    /// Saves one person's count for one day; zero removes it. Recorded in the history.
    func save(_ meal: MealCount, in group: GroupID, actor: MemberID?) async throws
}

/// Why someone can't be taken out of a group.
public enum MemberRemovalError: Error, Equatable, Sendable {
    /// The person using this phone.
    case isMe
    /// They keep the mess's books.
    case isManager
    /// An expense, payment or meal count mentions them, so removing them would change
    /// balances or history.
    case hasEntries
}
