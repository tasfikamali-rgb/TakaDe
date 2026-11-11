import XCTest
import TakaDeCore
@testable import TakaDePersistence

final class SQLiteLedgerRepositoryTests: XCTestCase {
    func makeGroup() -> ExpenseGroup {
        ExpenseGroup(name: "Cox's Bazar trip", members: [Member(displayName: "রিশান", isMe: true), Member(displayName: "Zawad")])
    }

    func testRoundTripPreservesNamesExactly() async throws {
        let repo = try SQLiteLedgerRepository()
        let group = makeGroup()
        try await repo.save(group, actor: group.members[0].id)
        let loaded = try await repo.group(group.id)
        XCTAssertEqual(loaded?.members.map(\.displayName), ["রিশান", "Zawad"])
        XCTAssertEqual(loaded?.name, "Cox's Bazar trip")
    }

    func testSimplifyDebtsSettingRoundTrips() async throws {
        let repo = try SQLiteLedgerRepository()
        var group = makeGroup()
        try await repo.save(group, actor: group.members[0].id)
        let fresh = try await repo.group(group.id)
        XCTAssertEqual(fresh?.simplifiesDebts, true)
        group.simplifiesDebts = false
        try await repo.save(group, actor: group.members[0].id)
        let loaded = try await repo.group(group.id)
        XCTAssertEqual(loaded?.simplifiesDebts, false)
    }

    func testExpenseSaveDeleteAndHistory() async throws {
        let repo = try SQLiteLedgerRepository()
        let group = makeGroup()
        let me = group.members[0].id, other = group.members[1].id
        try await repo.save(group, actor: me)

        let expense = try Expense(groupID: group.id, title: "Hotel", total: Money(minorUnits: 800_000), paidBy: [me: Money(minorUnits: 800_000)], splitRule: .equal([me, other]))
        try await repo.save(expense, actor: me)
        let loaded = try await repo.expenses(in: group.id, includeDeleted: false)
        XCTAssertEqual(loaded.first?.allocation.shares[other]?.minorUnits, 400_000)

        try await repo.delete(expense.id, actor: me)
        let afterDelete = try await repo.expenses(in: group.id, includeDeleted: false)
        XCTAssertTrue(afterDelete.isEmpty)
        let withDeleted = try await repo.expenses(in: group.id, includeDeleted: true)
        XCTAssertEqual(withDeleted.first?.version, 2)

        let history = try await repo.history(of: group.id)
        XCTAssertEqual(Set(history.map(\.action)), [.created, .deleted])
        XCTAssertEqual(history.count, 3) // group created, expense created, expense deleted
    }

    func testStorageRefusesUnverifiedConfirmation() async throws {
        let repo = try SQLiteLedgerRepository()
        let group = makeGroup()
        try await repo.save(group, actor: nil)
        var s = try Settlement(groupID: group.id, from: group.members[1].id, to: group.members[0].id, amount: Money(minorUnits: 100), method: .bkash)
        try s.transition(to: .reportedUnverified)
        try await repo.save(s, actor: nil)

        try s.transition(to: .confirmed, withProviderEvidence: true)
        do {
            try await repo.save(s, actor: nil)
            XCTFail("storage must not accept confirmation without a provider evidence path")
        } catch {}
    }

    func testMigratesFileDatabaseTwice() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try SQLiteLedgerRepository(path: url.path)
        _ = try SQLiteLedgerRepository(path: url.path) // reopening must be a no-op
    }
}
