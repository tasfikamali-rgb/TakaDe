import Foundation

/// The storage boundary. UI and view models talk to this, never to SQL.
public protocol LedgerRepository: Sendable {
    func groups() async throws -> [ExpenseGroup]
    func group(_ id: GroupID) async throws -> ExpenseGroup?
    func save(_ group: ExpenseGroup, actor: MemberID?) async throws

    func expenses(in group: GroupID, includeDeleted: Bool) async throws -> [Expense]
    func save(_ expense: Expense, actor: MemberID?) async throws
    func delete(_ expense: ExpenseID, actor: MemberID?) async throws

    func settlements(in group: GroupID) async throws -> [Settlement]
    func save(_ settlement: Settlement, actor: MemberID?) async throws

    func history(of group: GroupID) async throws -> [AuditEvent]
}
