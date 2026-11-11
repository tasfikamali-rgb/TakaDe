import XCTest
@testable import TakaDeCore

final class GroupSummaryTests: XCTestCase {
    func testSummaryListsTransfersWithNamesUnchanged() throws {
        let a = Member(displayName: "রিশান", isMe: true), b = Member(displayName: "Zawad")
        let group = ExpenseGroup(name: "Flat 4B", members: [a, b])
        let e = try Expense(groupID: group.id, title: "Secret gift", total: Money(minorUnits: 1000_00), paidBy: [a.id: Money(minorUnits: 1000_00)], splitRule: .equal([a.id, b.id]))
        let balances = try BalanceCalculator.balances(members: [a.id, b.id], currency: .bdt, expenses: [e], settlements: [])
        let summary = GroupSummary(group: group, balances: balances)
        XCTAssertEqual(summary.lines, [.init(from: "Zawad", to: "রিশান", amount: Money(minorUnits: 500_00))])
        XCTAssertFalse(summary.isSettled)
    }
}
