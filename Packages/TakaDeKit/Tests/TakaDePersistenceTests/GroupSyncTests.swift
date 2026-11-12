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
        XCTAssertEqual(joined?.members.contains(where: \.isMe), false)
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

    func testEditsFromAnotherPhoneSayWhoMadeThem() async throws {
        let (phone, group, expense) = try await makeShared()
        try await phone.startSharing(group.id)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(try await phone.pendingChanges(in: group.id, limit: 100)), in: group.id, syncedAt: Date())
        let rafi = group.members[1].id

        // Rafi changes the amount and records a payment on their phone.
        var edited = expense
        edited.total = Money(minorUnits: 360_000)
        edited.paidBy = [group.members[0].id: Money(minorUnits: 360_000)]
        edited.allocation = try SplitCalculator.allocate(edited.total, by: edited.splitRule)
        edited.version += 1
        try await friend.save(edited, actor: rafi)
        var payment = try Settlement(groupID: group.id, from: rafi, to: group.members[0].id, amount: Money(minorUnits: 150_000), method: .cash)
        try payment.transition(to: .reportedUnverified)
        try await friend.save(payment, actor: rafi)
        try payment.edit(amount: Money(minorUnits: 180_000), method: .bkash, userReference: "8N7A", by: rafi)
        try await friend.save(payment, actor: rafi)

        let fromFriend = try await friend.pendingChanges(in: group.id, limit: 100)
        XCTAssertEqual(fromFriend.count, 3)
        let result = try await phone.apply(relay(fromFriend, from: 2), in: group.id, syncedAt: Date())
        XCTAssertEqual(result.rejected, 0)

        let history = try await phone.history(of: group.id).filter { $0.source == .sync }
        XCTAssertEqual(history.count, 3)
        XCTAssertTrue(history.allSatisfy { $0.actor == rafi })
        let settlements = try await phone.settlements(in: group.id)
        XCTAssertEqual(settlements.first?.amount, Money(minorUnits: 180_000))
        XCTAssertEqual(settlements.first?.method, .bkash)
        let expenses = try await phone.expenses(in: group.id, includeDeleted: false)
        XCTAssertEqual(expenses.first?.total, Money(minorUnits: 360_000))
    }

    /// Notifications are built from these, so this phone's own changes must never be in them.
    func testOnlyOtherPhonesChangesAreReportedBack() async throws {
        let (phone, group, expense) = try await makeShared()
        try await phone.startSharing(group.id)
        let own = try await phone.pendingChanges(in: group.id, limit: 100)
        try await phone.markUploaded(own.map(\.id))
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(own), in: group.id, syncedAt: Date())
        let rafi = group.members[1].id

        var edited = expense
        edited.title = "Hotel (2 nights)"
        edited.version += 1
        try await friend.save(edited, actor: rafi)
        let fromFriend = try await friend.pendingChanges(in: group.id, limit: 100)

        // The relay sends this phone its own changes back first, then Rafi's.
        let result = try await phone.apply(relay(own) + relay(fromFriend, from: Int64(own.count)), in: group.id, syncedAt: Date())
        XCTAssertEqual(result.rejected, 0)
        XCTAssertEqual(result.fromOthers.map(\.action), [.edited])
        guard case .expense(let received)? = result.fromOthers.first?.item else { return XCTFail("Expected Rafi's expense") }
        XCTAssertEqual(received.title, "Hotel (2 nights)")
        XCTAssertEqual(received.changedBy, rafi)

        // A late, older copy changes nothing here, so there's nothing to tell anyone.
        let stale = SyncChange(groupID: group.id, entity: .expense, body: try JSONEncoder.iso.encode(expense))
        let again = try await phone.apply([ReceivedChange(sequence: 20, change: stale)], in: group.id, syncedAt: Date())
        XCTAssertTrue(again.fromOthers.isEmpty)
    }

    func testPayerCannotChangeAnAmountTheRecipientMarkedReceived() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(try await phone.pendingChanges(in: group.id, limit: 100)), in: group.id, syncedAt: Date())
        let me = group.members[0].id, rafi = group.members[1].id

        // Rafi paid; this phone (the recipient) marked it received.
        var payment = try Settlement(groupID: group.id, from: rafi, to: me, amount: Money(minorUnits: 150_000), method: .cash)
        try payment.acknowledge(by: me)
        try await phone.save(payment, actor: me)
        _ = try await friend.apply(relay(Array(try await phone.pendingChanges(in: group.id, limit: 100).suffix(1)), from: 2),
                                   in: group.id, syncedAt: Date())

        // A changed copy claiming to be from Rafi is refused on both phones.
        var forged = payment
        forged.changedBy = rafi
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder.iso.encode(forged)) as! [String: Any]
        var changed = raw
        changed["amount"] = try JSONSerialization.jsonObject(with: JSONEncoder.iso.encode(Money(minorUnits: 1_000)))
        let body = try JSONSerialization.data(withJSONObject: changed)
        let result = try await phone.apply([ReceivedChange(sequence: 10, change: SyncChange(groupID: group.id, entity: .settlement, body: body))],
                                           in: group.id, syncedAt: Date())
        XCTAssertEqual(result.rejected, 1)
        var local = try await friend.settlements(in: group.id).first!
        XCTAssertThrowsError(try local.edit(amount: Money(minorUnits: 1_000), method: .cash, userReference: nil, by: rafi))
        let kept = try await phone.settlements(in: group.id)
        XCTAssertEqual(kept.first?.amount, Money(minorUnits: 150_000))
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

    func testOversizedTextFromAnotherPhoneIsRejected() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        let sent = try await phone.pendingChanges(in: group.id, limit: 100)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(sent), in: group.id, syncedAt: Date())

        var renamed = group.forSharing
        renamed.name = String(repeating: "ক", count: SyncLimits.maxGroupNameLength + 1)
        let longName = SyncChange(groupID: group.id, entity: .group, body: try JSONEncoder.iso.encode(renamed))
        let payer = group.members[0].id
        let longTitle = try Expense(groupID: group.id, title: String(repeating: "x", count: SyncLimits.maxExpenseTitleLength + 1),
                                    total: Money(minorUnits: 100), paidBy: [payer: Money(minorUnits: 100)], splitRule: .equal([payer]))
        let titleChange = SyncChange(groupID: group.id, entity: .expense, body: try JSONEncoder.iso.encode(longTitle))
        let result = try await friend.apply([ReceivedChange(sequence: 3, change: longName), ReceivedChange(sequence: 4, change: titleChange)],
                                            in: group.id, syncedAt: Date())
        XCTAssertEqual(result.rejected, 2)
        let kept = try await friend.group(group.id)
        XCTAssertEqual(kept?.name, group.name)
    }

    func testEraseEverythingForgetsSharing() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        try await phone.eraseEverything()
        let shared = try await phone.sharedGroups()
        XCTAssertTrue(shared.isEmpty)
    }

    // MARK: Deleting a group for everyone

    private func deletion(of group: GroupID, by member: MemberID) throws -> SyncChange {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return SyncChange(groupID: group, entity: .groupDeleted, body: try encoder.encode(GroupDeletion(groupID: group, deletedBy: member)))
    }

    private func joinedFriend(of phone: SQLiteLedgerRepository, group: ExpenseGroup) async throws -> (SQLiteLedgerRepository, Int64) {
        try await phone.startSharing(group.id)
        let sent = try await phone.pendingChanges(in: group.id, limit: 100)
        let friend = try SQLiteLedgerRepository()
        try await friend.prepareToJoin(group.id)
        _ = try await friend.apply(relay(sent), in: group.id, syncedAt: Date())
        try await friend.setMe(group.members[1].id, in: group.id)
        return (friend, Int64(sent.count))
    }

    func testMakersDeletionDeletesTheGroupOnOtherPhones() async throws {
        let (phone, group, _) = try await makeShared()
        let (friend, last) = try await joinedFriend(of: phone, group: group)
        // A change after the deletion in the same batch is not applied: the group stays gone.
        var renamed = group
        renamed.name = "Back again"
        let later = SyncChange(groupID: group.id, entity: .group, body: try JSONEncoder.iso.encode(renamed.forSharing))
        let result = try await friend.apply(relay([try deletion(of: group.id, by: group.members[0].id), later], from: last),
                                            in: group.id, syncedAt: Date())
        XCTAssertTrue(result.groupDeleted)
        let gone = try await friend.group(group.id)
        XCTAssertNil(gone)
        let expenses = try await friend.expenses(in: group.id, includeDeleted: true)
        XCTAssertTrue(expenses.isEmpty)
        let history = try await friend.history(of: group.id)
        XCTAssertTrue(history.isEmpty)
        let state = try await friend.sharedState(of: group.id)
        XCTAssertNil(state)
    }

    func testDeletionFromSomeoneElseIsIgnored() async throws {
        let (phone, group, _) = try await makeShared()
        let (friend, last) = try await joinedFriend(of: phone, group: group)
        let result = try await friend.apply(relay([try deletion(of: group.id, by: group.members[1].id)], from: last),
                                            in: group.id, syncedAt: Date())
        XCTAssertFalse(result.groupDeleted)
        XCTAssertEqual(result.rejected, 1)
        let still = try await friend.group(group.id)
        XCTAssertNotNil(still)
    }

    func testRecordedMakerCantBeChangedByAnotherPhone() async throws {
        let phone = try SQLiteLedgerRepository()
        let me = Member(displayName: "Sabit", isMe: true)
        let rafi = Member(displayName: "Rafi")
        let group = ExpenseGroup(name: "Car", members: [me, rafi], createdBy: me.id)
        try await phone.save(group, actor: me.id)
        let (friend, last) = try await joinedFriend(of: phone, group: group)
        let joined = try await friend.group(group.id)
        XCTAssertEqual(joined?.createdBy, me.id)

        var hijack = group.forSharing
        hijack.createdBy = rafi.id
        let change = SyncChange(groupID: group.id, entity: .group, body: try JSONEncoder.iso.encode(hijack))
        _ = try await friend.apply(relay([change], from: last), in: group.id, syncedAt: Date())
        let after = try await friend.group(group.id)
        XCTAssertEqual(after?.createdBy, me.id)
    }

    func testDeletingLocallyRemovesEverything() async throws {
        let (phone, group, _) = try await makeShared()
        try await phone.startSharing(group.id)
        try await phone.deleteGroup(group.id)
        let gone = try await phone.group(group.id)
        XCTAssertNil(gone)
        let pending = try await phone.pendingChanges(in: group.id, limit: 100)
        XCTAssertTrue(pending.isEmpty)
        let history = try await phone.history(of: group.id)
        XCTAssertTrue(history.isEmpty)
        // History stays append-only for everything else.
        let other = ExpenseGroup(name: "Flat", members: [Member(displayName: "Sabit", isMe: true)])
        try await phone.save(other, actor: nil)
        let otherHistory = try await phone.history(of: other.id)
        XCTAssertEqual(otherHistory.count, 1)
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
