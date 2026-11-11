import XCTest
import TakaDeCore
@testable import TakaDePersistence

/// Two in-memory databases stand in for two phones; the "relay" is an array in the test.
final class GroupSyncTests: XCTestCase {
    private func relay(_ changes: [SyncChange], from start: Int64 = 0) -> [ReceivedChange] {
        changes.enumerated().map { ReceivedChange(sequence: start + Int64($0.offset) + 1, change: $0.element) }
    }

    private func makeShared() async throws -> (SQLiteLedgerRepository, ExpenseGroup, Expense) {
        let phone = try SQLiteLedgerRepository()
        let group = ExpenseGroup(name: "Sylhet trip", members: [Member(displayName: "সাবিত", isMe: true), Member(displayName: "Rafi")])
        try await phone.save(group, actor: group.members[0].id)
        let expense = try Expense(groupID: group.id, title: "Hotel", total: Money(minorUnits: 300_000),
                                  paidBy: [group.members[0].id: Money(minorUnits: 300_000)],
                                  splitRule: .equal(group.members.map(\.id)))
        try await phone.save(expense, actor: group.members[0].id)
        return (phone, group, expense)
    }

    func testUnsharedGroupsQueueNothing() async throws {
        let (phone, group, _) = try await makeShared()
        let pending = try await phone.pendingChanges(in: group.id, limit: 100)
        XCTAssertTrue(pending.isEmpty)
    }

    func testSharingQueuesEverythingAndLaterEdits() async throws {
        let (phone, group, expense) = try await makeShared()
        try await phone.startSharing(group.id)
        var pending = try await phone.pendingChanges(in: group.id, limit: 100)
        XCTAssertEqual(pending.map(\.entity), [.group, .expense])
        // Nobody is "me" in what other phones receive.
        let sent = try JSONDecoder.iso.decode(ExpenseGroup.self, from: pending[0].body)
        XCTAssertFalse(sent.members.contains(where: \.isMe))

        try await phone.delete(expense.id, actor: nil)
        pending = try await phone.pendingChanges(in: group.id, limit: 100)
        XCTAssertEqual(pending.count, 3)

        try await phone.markUploaded(pending.map(\.id))
        let after = try await phone.pendingChanges(in: group.id, limit: 100)
        XCTAssertTrue(after.isEmpty)
    }

    func testJoiningPhoneGetsTheGroupAndChoosesWhoItIs() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        let sent = try await phone.pendingChanges(in: group.id, limit: 100)

        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        let result = try await friend.apply(relay(sent), in: group.id, syncedAt: Date())
        XCTAssertEqual(result.applied, 2)
        XCTAssertEqual(result.rejected, 0)

        let joined = try await friend.group(group.id)
        XCTAssertEqual(joined?.members.map(\.displayName), ["সাবিত", "Rafi"])
        XCTAssertNil(joined?.me)
        let expenses = try await friend.expenses(in: group.id, includeDeleted: false)
        XCTAssertEqual(expenses.count, 1)

        try await friend.setMe(group.members[1].id, in: group.id)
        let chosen = try await friend.group(group.id)
        XCTAssertEqual(chosen?.members.first(where: \.isMe)?.displayName, "Rafi")

        // Applied changes are not sent back, and the cursor moved.
        let echo = try await friend.pendingChanges(in: group.id, limit: 100)
        XCTAssertTrue(echo.isEmpty)
        let state = try await friend.sharedState(of: group.id)
        XCTAssertEqual(state?.cursor, 2)

        // A later group change from the first phone keeps this phone's "me".
        var renamed = group
        renamed.name = "Sylhet trip 2026"
        try await phone.save(renamed, actor: nil)
        let next = try await phone.pendingChanges(in: group.id, limit: 100).last!
        _ = try await friend.apply([ReceivedChange(sequence: 3, change: next)], in: group.id, syncedAt: Date())
        let updated = try await friend.group(group.id)
        XCTAssertEqual(updated?.name, "Sylhet trip 2026")
        XCTAssertEqual(updated?.members.first(where: \.isMe)?.displayName, "Rafi")

        // History marks where the change came from.
        let history = try await friend.history(of: group.id)
        XCTAssertTrue(history.allSatisfy { $0.source == .sync })
    }

    func testOlderExpenseVersionDoesNotOverwriteNewer() async throws {
        let (phone, group, expense) = try await makeShared()
        try await phone.startSharing(group.id)
        let sent = try await phone.pendingChanges(in: group.id, limit: 100)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(sent), in: group.id, syncedAt: Date())

        var edited = expense
        edited.title = "Hotel (2 nights)"
        edited.version = 3
        try await friend.save(edited, actor: nil)
        // The original version 1 arrives again, later in relay order.
        let stale = SyncChange(groupID: group.id, entity: .expense, body: try JSONEncoder.iso.encode(expense))
        _ = try await friend.apply([ReceivedChange(sequence: 10, change: stale)], in: group.id, syncedAt: Date())
        let kept = try await friend.expenses(in: group.id, includeDeleted: false).first
        XCTAssertEqual(kept?.title, "Hotel (2 nights)")
    }

    func testAnotherPhoneCannotMarkAPaymentConfirmed() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        let sent = try await phone.pendingChanges(in: group.id, limit: 100)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(sent), in: group.id, syncedAt: Date())

        var forged = try Settlement(groupID: group.id, from: group.members[1].id, to: group.members[0].id,
                                    amount: Money(minorUnits: 150_000), method: .bkash, status: .reportedUnverified)
        try forged.transition(to: .confirmed, withProviderEvidence: true)
        let change = SyncChange(groupID: group.id, entity: .settlement, body: try JSONEncoder.iso.encode(forged))
        let result = try await friend.apply([ReceivedChange(sequence: 3, change: change)], in: group.id, syncedAt: Date())
        XCTAssertEqual(result.rejected, 1)
        let settlements = try await friend.settlements(in: group.id)
        XCTAssertTrue(settlements.isEmpty)
        // The bad change is skipped, not retried forever.
        let state = try await friend.sharedState(of: group.id)
        XCTAssertEqual(state?.cursor, 3)
    }

    func testExpenseForSomeoneOutsideTheGroupIsRejected() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        let sent = try await phone.pendingChanges(in: group.id, limit: 100)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(sent), in: group.id, syncedAt: Date())

        let stranger = MemberID()
        let bad = try Expense(groupID: group.id, title: "?", total: Money(minorUnits: 100), paidBy: [stranger: Money(minorUnits: 100)],
                              splitRule: .equal([stranger]))
        let change = SyncChange(groupID: group.id, entity: .expense, body: try JSONEncoder.iso.encode(bad))
        let result = try await friend.apply([ReceivedChange(sequence: 3, change: change)], in: group.id, syncedAt: Date())
        XCTAssertEqual(result.rejected, 1)
    }

    func testEraseEverythingForgetsSharing() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        try await phone.eraseEverything()
        let shared = try await phone.sharedGroups()
        XCTAssertTrue(shared.isEmpty)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
