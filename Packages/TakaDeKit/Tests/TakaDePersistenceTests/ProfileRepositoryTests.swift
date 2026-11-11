import XCTest
import TakaDeCore
@testable import TakaDePersistence

final class ProfileRepositoryTests: XCTestCase {
    func testProfileRoundTripKeepsNameAndAccountButNoTokens() async throws {
        let repo = try SQLiteLedgerRepository()
        let account = LinkedAccount(provider: .apple, providerUserID: "001234.abcd", email: "x@privaterelay.appleid.com")
        let profile = LocalProfile(displayName: "সাবিত", languageCode: "bn", digitStyle: "bengali", account: account)
        try await repo.save(profile)
        let loaded = try await repo.profile()
        XCTAssertEqual(loaded?.displayName, "সাবিত")
        XCTAssertEqual(loaded?.account, account)
        XCTAssertEqual(loaded?.languageCode, "bn")
    }

    func testAccountAndIdentitiesRoundTripAndAreErased() async throws {
        let repo = try SQLiteLedgerRepository()
        let profile = LocalProfile(displayName: "Sabit", accountID: "8f1c-uuid", accountEmail: "sabit@example.com")
        try await repo.save(profile)
        let linked = Date(timeIntervalSince1970: 1_800_000_000)
        let identities = [
            AccountIdentity(id: "id-1", provider: .email, providerUserID: "8f1c-uuid", email: "sabit@example.com", linkedAt: linked),
            AccountIdentity(id: "id-2", provider: .microsoft, providerUserID: "oid-1", email: nil, linkedAt: linked.addingTimeInterval(60)),
        ]
        try await repo.replaceAccountIdentities(identities)
        let loaded = try await repo.profile()
        XCTAssertEqual(loaded?.accountID, "8f1c-uuid")
        XCTAssertEqual(loaded?.accountEmail, "sabit@example.com")
        let storedIdentities = try await repo.accountIdentities()
        XCTAssertEqual(storedIdentities, identities)

        try await repo.replaceAccountIdentities([identities[0]])
        let afterUnlink = try await repo.accountIdentities()
        XCTAssertEqual(afterUnlink, [identities[0]])

        try await repo.eraseEverything()
        let afterErase = try await repo.accountIdentities()
        XCTAssertTrue(afterErase.isEmpty)
    }

    func testOnlyOneProfileIsKept() async throws {
        let repo = try SQLiteLedgerRepository()
        try await repo.save(LocalProfile(displayName: "A"))
        try await repo.save(LocalProfile(displayName: "B"))
        let loaded = try await repo.profile()
        XCTAssertEqual(loaded?.displayName, "B")
    }

    func testSignOutClearsTheAccount() async throws {
        let repo = try SQLiteLedgerRepository()
        var profile = LocalProfile(displayName: "Sabit", account: LinkedAccount(provider: .google, providerUserID: "123", email: nil))
        try await repo.save(profile)
        profile.account = nil
        try await repo.save(profile)
        let loaded = try await repo.profile()
        XCTAssertNil(loaded?.account)
    }

    func testPaymentHandlesBelongToAMember() async throws {
        let repo = try SQLiteLedgerRepository()
        let me = Member(displayName: "Sabit", isMe: true)
        let group = ExpenseGroup(name: "Flat", members: [me, Member(displayName: "Rafi")])
        try await repo.save(group, actor: me.id)
        let handle = try PaymentHandle(memberID: me.id, rail: .bkash, handle: "+8801712345678")
        try await repo.save(handle)
        var handles = try await repo.paymentHandles(for: me.id)
        XCTAssertEqual(handles.map(\.handle), ["01712345678"])
        try await repo.deletePaymentHandle(handle.id)
        handles = try await repo.paymentHandles(for: me.id)
        XCTAssertTrue(handles.isEmpty)
    }

    func testExportHoldsEverythingAndEraseRemovesIt() async throws {
        let repo = try SQLiteLedgerRepository()
        try await repo.save(LocalProfile(displayName: "Sabit"))
        let me = Member(displayName: "Sabit", isMe: true), rafi = Member(displayName: "Rafi")
        let group = ExpenseGroup(name: "Sajek", members: [me, rafi])
        try await repo.save(group, actor: me.id)
        let expense = try Expense(groupID: group.id, title: "Bus", total: Money(minorUnits: 120_000),
                                  paidBy: [me.id: Money(minorUnits: 120_000)], splitRule: .equal([me.id, rafi.id]))
        try await repo.save(expense, actor: me.id)

        let export = try await repo.export()
        XCTAssertEqual(export.profile?.displayName, "Sabit")
        XCTAssertEqual(export.groups.first?.expenses.map(\.title), ["Bus"])
        XCTAssertEqual(export.groups.first?.history.count, 2)
        XCTAssertNoThrow(try JSONEncoder().encode(export))

        try await repo.eraseEverything()
        let groups = try await repo.groups()
        let profile = try await repo.profile()
        let history = try await repo.history(of: group.id)
        XCTAssertTrue(groups.isEmpty)
        XCTAssertNil(profile)
        XCTAssertTrue(history.isEmpty)
    }

    func testHistoryStaysAppendOnlyAfterErase() async throws {
        let repo = try SQLiteLedgerRepository()
        let me = Member(displayName: "Sabit", isMe: true)
        try await repo.save(ExpenseGroup(name: "Flat", members: [me]), actor: me.id)
        try await repo.eraseEverything()
        try await repo.save(ExpenseGroup(name: "Again", members: [me]), actor: me.id)
        do {
            try await repo.writer.write { db in try db.execute(sql: "DELETE FROM audit_event") }
            XCTFail("History should still refuse deletes")
        } catch {}
    }
}
