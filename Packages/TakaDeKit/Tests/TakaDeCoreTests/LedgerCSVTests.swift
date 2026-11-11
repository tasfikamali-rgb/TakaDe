import XCTest
@testable import TakaDeCore

/// Synthetic data only.
final class LedgerCSVTests: XCTestCase {
    let rina = Member(displayName: "রিনা", isMe: true)
    let tom = Member(displayName: "Tom, Jr.")
    var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return cal
    }()

    func testExpenseAndPaymentRows() throws {
        let group = ExpenseGroup(name: "Flat", members: [rina, tom])
        let when = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let expense = try Expense(groupID: group.id, title: "Bazar \"big\"", total: Money(minorUnits: 1000),
                                  paidBy: [rina.id: Money(minorUnits: 1000)], splitRule: .equal([rina.id, tom.id]),
                                  occurredAt: when, category: .groceries)
        let payment = try Settlement(groupID: group.id, from: tom.id, to: rina.id, amount: Money(minorUnits: 500),
                                     method: .cash, status: .reportedUnverified, createdAt: when.addingTimeInterval(3600))
        let csv = LedgerCSV.make(group: group, expenses: [expense], settlements: [payment], calendar: calendar)
        let rows = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(rows[0], "Date,Type,Title,Category,Amount,Currency,Paid by,রিনা,\"Tom, Jr.\",Status")
        XCTAssertEqual(rows[1], "2026-11-03,Expense,\"Bazar \"\"big\"\"\",groceries,10.00,BDT,রিনা: 10.00,5.00,5.00,")
        XCTAssertEqual(rows[2], "2026-11-03,Payment,\"Tom, Jr. → রিনা\",,5.00,BDT,\"Tom, Jr.: 5.00\",5.00,,reported_unverified")
        XCTAssertEqual(rows.count, 4)
    }

    func testDeletedExpensesAreLeftOut() throws {
        let group = ExpenseGroup(name: "Flat", members: [rina, tom])
        var expense = try Expense(groupID: group.id, title: "Tea", total: Money(minorUnits: 100), paidBy: [rina.id: Money(minorUnits: 100)],
                                  splitRule: .equal([rina.id, tom.id]))
        expense.deletedAt = Date()
        XCTAssertEqual(LedgerCSV.make(group: group, expenses: [expense], settlements: [], calendar: calendar).components(separatedBy: "\r\n").count, 2)
    }

    func testFormulaLikeTextIsDefused() {
        XCTAssertEqual(LedgerCSV.escape("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(LedgerCSV.escape("@cmd"), "'@cmd")
        XCTAssertEqual(LedgerCSV.escape("-12.50"), "-12.50")
        XCTAssertEqual(LedgerCSV.escape("Rent"), "Rent")
    }

    func testNumbersUseLatinDigitsAndPadding() {
        XCTAssertEqual(LedgerCSV.number(Money(minorUnits: 125005)), "1250.05")
        XCTAssertEqual(LedgerCSV.number(Money(minorUnits: 7)), "0.07")
        XCTAssertEqual(LedgerCSV.number(Money(minorUnits: -150)), "-1.50")
    }
}
