import XCTest
@testable import TakaDeCore

final class BalanceTests: XCTestCase {
    let a = MemberID(), b = MemberID(), c = MemberID()
    let group = GroupID()

    func expense(_ total: Int64, paidBy payer: MemberID, among members: [MemberID]) throws -> Expense {
        try Expense(groupID: group, title: "Dinner", total: Money(minorUnits: total), paidBy: [payer: Money(minorUnits: total)], splitRule: .equal(members))
    }

    func testBalancesSumToZeroAndReflectWhoPaid() throws {
        let e1 = try expense(1200_00, paidBy: a, among: [a, b, c])
        let e2 = try expense(300_00, paidBy: b, among: [b, c])
        let bal = try BalanceCalculator.balances(members: [a, b, c], currency: .bdt, expenses: [e1, e2], settlements: [])
        XCTAssertEqual(bal.net(for: a).minorUnits, 800_00)
        XCTAssertEqual(bal.net(for: b).minorUnits, -400_00 + 150_00)
        XCTAssertEqual(bal.net(for: c).minorUnits, -400_00 - 150_00)
    }

    func testDeletedExpensesDoNotCount() throws {
        var e = try expense(900, paidBy: a, among: [a, b, c])
        e.deletedAt = Date()
        let bal = try BalanceCalculator.balances(members: [a, b, c], currency: .bdt, expenses: [e], settlements: [])
        XCTAssertTrue(bal.net.values.allSatisfy(\.isZero))
    }

    func testReportedSettlementCountsButIsFlaggedUnverified() throws {
        let e = try expense(1000, paidBy: a, among: [a, b])
        var s = try Settlement(groupID: group, from: b, to: a, amount: Money(minorUnits: 500), method: .bkash)
        let before = try BalanceCalculator.balances(members: [a, b], currency: .bdt, expenses: [e], settlements: [s])
        XCTAssertEqual(before.net(for: b).minorUnits, -500, "a not-started settlement must not reduce the debt")

        try s.transition(to: .reportedUnverified)
        let after = try BalanceCalculator.balances(members: [a, b], currency: .bdt, expenses: [e], settlements: [s])
        XCTAssertEqual(after.net(for: b).minorUnits, 0)
        XCTAssertEqual(after.unverifiedSettled[b]?.minorUnits, 500)
    }

    func testAcknowledgedSettlementIsNotCountedAsUnverified() throws {
        let e = try expense(1000, paidBy: a, among: [a, b])
        var s = try Settlement(groupID: group, from: b, to: a, amount: Money(minorUnits: 500), method: .cash)
        try s.acknowledge(by: a)
        let bal = try BalanceCalculator.balances(members: [a, b], currency: .bdt, expenses: [e], settlements: [s])
        XCTAssertEqual(bal.net(for: b).minorUnits, 0)
        XCTAssertNil(bal.unverifiedSettled[b])
    }

    func testUnknownMemberIsAnError() throws {
        let e = try expense(1000, paidBy: a, among: [a, b])
        XCTAssertThrowsError(try BalanceCalculator.balances(members: [a], currency: .bdt, expenses: [e], settlements: []))
    }

    func testSuggestedTransfersSettleEveryone() throws {
        let es = [try expense(900, paidBy: a, among: [a, b, c]), try expense(600, paidBy: b, among: [a, b, c])]
        let bal = try BalanceCalculator.balances(members: [a, b, c], currency: .bdt, expenses: es, settlements: [])
        let transfers = BalanceCalculator.suggestedTransfers(bal)
        XCTAssertLessThanOrEqual(transfers.count, 2)

        var net = bal.net.mapValues(\.minorUnits)
        for t in transfers { net[t.from]! += t.amount.minorUnits; net[t.to]! -= t.amount.minorUnits }
        XCTAssertTrue(net.values.allSatisfy { $0 == 0 })
    }
}
