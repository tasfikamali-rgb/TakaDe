import XCTest
@testable import TakaDeCore

final class GroupNoticeTests: XCTestCase {
    private let me = Member(displayName: "সাবিত", isMe: true)
    private let rafi = Member(displayName: "Rafi")
    private let nila = Member(displayName: "Nila")

    private lazy var group = ExpenseGroup(name: "Sylhet trip", members: [me, rafi, nila])

    private func expense(paidBy payer: Member, among people: [Member], total: Int64 = 90_000, by author: Member? = nil, deleted: Bool = false) throws -> Expense {
        var expense = try Expense(groupID: group.id, title: "Hotel", total: Money(minorUnits: total),
                                  paidBy: [payer.id: Money(minorUnits: total)], splitRule: .equal(people.map(\.id)),
                                  deletedAt: deleted ? Date() : nil)
        expense.changedBy = author?.id
        return expense
    }

    private func payment(from: Member, to: Member, status: SettlementStatus = .reportedUnverified, by author: Member?) throws -> Settlement {
        var settlement = try Settlement(groupID: group.id, from: from.id, to: to.id, amount: Money(minorUnits: 50_000), method: .bkash, status: status)
        settlement.changedBy = author?.id
        return settlement
    }

    func testExpenseWithMyShareSaysWhoAddedItAndMyPart() throws {
        let added = try expense(paidBy: rafi, among: [me, rafi, nila], by: rafi)
        let notice = GroupNotice.make(group: group, changes: [AppliedChange(.expense(added), action: .created)], myBalance: Money(minorUnits: -30_000))
        XCTAssertEqual(notice?.events, [.expense(title: "Hotel", action: .created, by: rafi.id, myShare: Money(minorUnits: 30_000))])
        XCTAssertEqual(notice?.myBalance, Money(minorUnits: -30_000))
    }

    func testExpenseIPaidForButHaveNoShareInStillCounts() throws {
        let added = try expense(paidBy: me, among: [rafi, nila], by: rafi)
        let notice = GroupNotice.make(group: group, changes: [AppliedChange(.expense(added), action: .edited)], myBalance: nil)
        XCTAssertEqual(notice?.events, [.expense(title: "Hotel", action: .edited, by: rafi.id, myShare: nil)])
    }

    func testExpenseIAmNotPartOfSaysNothing() throws {
        let other = try expense(paidBy: rafi, among: [rafi, nila], by: rafi)
        XCTAssertNil(GroupNotice.make(group: group, changes: [AppliedChange(.expense(other), action: .created)], myBalance: nil))
    }

    func testDeletedExpenseHasNoShare() throws {
        let gone = try expense(paidBy: rafi, among: [me, rafi], by: rafi, deleted: true)
        let notice = GroupNotice.make(group: group, changes: [AppliedChange(.expense(gone), action: .deleted)], myBalance: nil)
        XCTAssertEqual(notice?.events, [.expense(title: "Hotel", action: .deleted, by: rafi.id, myShare: nil)])
    }

    func testMyOwnChangesFromAnotherPhoneSayNothing() throws {
        let mine = try expense(paidBy: me, among: [me, rafi], by: me)
        XCTAssertNil(GroupNotice.make(group: group, changes: [AppliedChange(.expense(mine), action: .created)], myBalance: nil))
    }

    func testNothingWhenThisPhoneHasNotChosenWhoItIs() throws {
        var unknown = group
        unknown.members = unknown.members.map { Member(id: $0.id, displayName: $0.displayName) }
        let added = try expense(paidBy: rafi, among: [me, rafi], by: rafi)
        XCTAssertNil(GroupNotice.make(group: unknown, changes: [AppliedChange(.expense(added), action: .created)], myBalance: nil))
    }

    func testSomeoneRecordingThatTheyPaidMe() throws {
        let paid = try payment(from: rafi, to: me, by: rafi)
        let notice = GroupNotice.make(group: group, changes: [AppliedChange(.settlement(paid), action: .created)], myBalance: .zero(.bdt))
        XCTAssertEqual(notice?.events, [.paidYou(by: rafi.id, amount: Money(minorUnits: 50_000))])
    }

    func testThePersonIPaidMarkingItReceived() throws {
        let received = try payment(from: me, to: rafi, status: .acknowledgedByRecipient, by: rafi)
        let notice = GroupNotice.make(group: group, changes: [AppliedChange(.settlement(received), action: .statusChanged)], myBalance: nil)
        XCTAssertEqual(notice?.events, [.markedReceived(by: rafi.id, amount: Money(minorUnits: 50_000))])
    }

    func testOtherPaymentChangesAndPaymentsBetweenOthers() throws {
        let withdrawn = try payment(from: rafi, to: me, status: .reversed, by: rafi)
        let between = try payment(from: rafi, to: nila, by: rafi)
        let notice = GroupNotice.make(group: group, changes: [
            AppliedChange(.settlement(withdrawn), action: .statusChanged),
            AppliedChange(.settlement(between), action: .created),
        ], myBalance: nil)
        XCTAssertEqual(notice?.events, [.paymentChanged(by: rafi.id, amount: Money(minorUnits: 50_000))])
    }

    func testMyOwnPaymentFromAnotherPhoneSaysNothing() throws {
        let mine = try payment(from: me, to: rafi, by: me)
        XCTAssertNil(GroupNotice.make(group: group, changes: [AppliedChange(.settlement(mine), action: .created)], myBalance: nil))
    }
}
