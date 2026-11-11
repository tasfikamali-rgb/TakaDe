import XCTest
@testable import TakaDeCore

final class ExpenseCategoryTests: XCTestCase {
    func testGuessesFromEnglishAndBengaliTitles() {
        XCTAssertEqual(ExpenseCategory.guess(from: "Kacchi at Star"), .food)
        XCTAssertEqual(ExpenseCategory.guess(from: "Pathao to Gulshan"), .transport)
        XCTAssertEqual(ExpenseCategory.guess(from: "বাজার"), .groceries)
        XCTAssertEqual(ExpenseCategory.guess(from: "Flat rent November"), .rent)
        XCTAssertEqual(ExpenseCategory.guess(from: "Sea Pearl hotel"), .stay)
        XCTAssertNil(ExpenseCategory.guess(from: "Misc"))
    }

    func testExpenseWithoutCategoryStillDecodes() throws {
        let a = MemberID()
        let expense = try Expense(groupID: GroupID(), title: "Tea", total: Money(minorUnits: 40_00),
                                  paidBy: [a: Money(minorUnits: 40_00)], splitRule: .equal([a]))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(expense)) as! [String: Any]
        json.removeValue(forKey: "category")
        let decoded = try JSONDecoder().decode(Expense.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.category)
        XCTAssertEqual(decoded.title, "Tea")
    }
}
