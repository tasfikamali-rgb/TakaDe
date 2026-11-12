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

    func testNicknameRoundTripsAndNeverChangesTheName() async throws {
        let repo = try SQLiteLedgerRepository()
        var group = ExpenseGroup(name: "Flat", members: [Member(displayName: "Sabit", isMe: true), Member(displayName: "Rishan Ahmed")])
        try await repo.save(group, actor: group.members[0].id)
        group.members[1].nickname = "Rishu"
        try await repo.save(group, actor: group.members[0].id)
        let loaded = try await repo.group(group.id)
        XCTAssertEqual(loaded?.members[1].nickname, "Rishu")
        XCTAssertEqual(loaded?.members[1].displayName, "Rishan Ahmed")
        XCTAssertEqual(loaded?.members[1].shownName, "Rishu")
        XCTAssertNil(loaded?.members[0].nickname)
        XCTAssertEqual(loaded?.members[0].shownName, "Sabit")

        group.members[1].nickname = nil
        try await repo.save(group, actor: group.members[0].id)
        let cleared = try await repo.group(group.id)
        XCTAssertNil(cleared?.members[1].nickname)
    }

    func testGroupAccentRoundTrips() async throws {
        let repo = try SQLiteLedgerRepository()
        var group = ExpenseGroup(name: "Sajek", members: [Member(displayName: "Sabit", isMe: true), Member(displayName: "Zawad")])
        try await repo.save(group, actor: group.members[0].id)
        let plain = try await repo.group(group.id)
        XCTAssertNil(plain?.accentHex)
        group.accentHex = "#2E7D5B"
        try await repo.save(group, actor: group.members[0].id)
        let tinted = try await repo.group(group.id)
        XCTAssertEqual(tinted?.accentHex, "#2E7D5B")
    }

    func testRemovingAMemberOnlyWhileNothingMentionsThem() async throws {
        let repo = try SQLiteLedgerRepository()
        let me = Member(displayName: "Sabit", isMe: true)
        let zawad = Member(displayName: "Zawad")
        let rishan = Member(displayName: "Rishan")
        let group = ExpenseGroup(name: "Flat", members: [me, zawad, rishan])
        try await repo.save(group, actor: me.id)
        let dinner = try Expense(groupID: group.id, title: "Dinner", total: Money(minorUnits: 600, currency: group.currency),
                                 paidBy: [me.id: Money(minorUnits: 600, currency: group.currency)], splitRule: .equal([me.id, rishan.id]))
        try await repo.save(dinner, actor: me.id)

        // Zawad was added by mistake and is in nothing: removed.
        try await repo.removeMember(zawad.id, from: group.id, actor: me.id)
        let afterRemove = try await repo.group(group.id)
        XCTAssertEqual(afterRemove?.members.map(\.displayName), ["Sabit", "Rishan"])

        // Rishan is in an expense, even a deleted one: kept.
        try await repo.delete(dinner.id, actor: me.id)
        do {
            try await repo.removeMember(rishan.id, from: group.id, actor: me.id)
            XCTFail("Rishan is in an expense")
        } catch let error as MemberRemovalError {
            XCTAssertEqual(error, .hasEntries)
        }
        do {
            try await repo.removeMember(me.id, from: group.id, actor: me.id)
            XCTFail("Can't remove yourself")
        } catch let error as MemberRemovalError {
            XCTAssertEqual(error, .isMe)
        }
        let kept = try await repo.group(group.id)
        XCTAssertEqual(kept?.members.count, 2)
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

    func testMessGroupAndMealCountsRoundTrip() async throws {
        let repo = try SQLiteLedgerRepository()
        var group = makeGroup()
        let me = group.members[0].id, other = group.members[1].id
        group.kind = .mess
        group.managerID = me
        try await repo.save(group, actor: me)
        let loaded = try await repo.group(group.id)
        XCTAssertEqual(loaded?.kind, .mess)
        XCTAssertEqual(loaded?.managerID, me)

        let day = MealDay(year: 2026, month: 11, day: 5)!
        try await repo.save(try MealCount(memberID: other, day: day, halfMeals: 3), in: group.id, actor: me)
        try await repo.save(try MealCount(memberID: other, day: day, halfMeals: 4), in: group.id, actor: me)
        try await repo.save(try MealCount(memberID: me, day: MealDay(year: 2026, month: 12, day: 1)!, halfMeals: 2), in: group.id, actor: me)
        let november = try await repo.mealCounts(in: group.id, month: MessMonth(year: 2026, month: 11)!)
        XCTAssertEqual(november.count, 1)
        XCTAssertEqual(november.first?.halfMeals, 4)

        try await repo.save(try MealCount(memberID: other, day: day, halfMeals: 0), in: group.id, actor: me)
        let cleared = try await repo.mealCounts(in: group.id, month: MessMonth(year: 2026, month: 11)!)
        XCTAssertTrue(cleared.isEmpty)
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
