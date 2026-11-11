import XCTest
@testable import TakaDeCore

/// Synthetic mess data only.
final class MessTests: XCTestCase {
    let a = MemberID(), b = MemberID(), c = MemberID()
    var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return cal
    }()
    let november = MessMonth(year: 2026, month: 11)!

    func day(_ d: Int, month: Int = 11) -> MealDay { MealDay(year: 2026, month: month, day: d)! }

    func date(_ d: Int, month: Int = 11) -> Date { day(d, month: month).date(calendar: calendar) }

    func bazar(_ taka: Int64, paidBy payer: MemberID, on d: Int, month: Int = 11) throws -> Expense {
        try Expense(groupID: GroupID(), title: "Bazar", total: Money(minorUnits: taka * 100), paidBy: [payer: Money(minorUnits: taka * 100)],
                    splitRule: .equal([a, b, c]), occurredAt: date(d, month: month), category: .groceries)
    }

    func meals(_ member: MemberID, _ halves: Int, on d: Int, month: Int = 11) throws -> MealCount {
        try MealCount(memberID: member, day: day(d, month: month), halfMeals: halves)
    }

    func testMealCostFollowsMealsEaten() throws {
        // 3,000 taka of bazar; A ate 20 meals, B 10, C 0.
        let expenses = [try bazar(2000, paidBy: a, on: 3), try bazar(1000, paidBy: b, on: 15)]
        let counts = [try meals(a, 40, on: 1), try meals(b, 20, on: 1)]
        let summary = try MessMonthSummary(month: november, members: [a, b, c], meals: counts, expenses: expenses, currency: .bdt, calendar: calendar)
        XCTAssertEqual(summary.bazarTotal.minorUnits, 3000_00)
        XCTAssertEqual(summary.totalHalfMeals, 60)
        XCTAssertEqual(summary.mealRate?.minorUnits, 100_00)
        XCTAssertEqual(summary.mealCost[a]?.minorUnits, 2000_00)
        XCTAssertEqual(summary.mealCost[b]?.minorUnits, 1000_00)
        XCTAssertEqual(summary.mealCost[c]?.minorUnits, 0)
        XCTAssertEqual(summary.mealSplitRule, .shares([a: 40, b: 20]))
    }

    func testCostsAlwaysAddUpToBazarTotal() throws {
        let expenses = [try bazar(1001, paidBy: a, on: 2), try bazar(337, paidBy: c, on: 9)]
        let counts = [try meals(a, 7, on: 1), try meals(b, 5, on: 2), try meals(c, 3, on: 3)]
        let summary = try MessMonthSummary(month: november, members: [a, b, c], meals: counts, expenses: expenses, currency: .bdt, calendar: calendar)
        let sum = summary.mealCost.values.reduce(Int64(0)) { $0 + $1.minorUnits }
        XCTAssertEqual(sum, summary.bazarTotal.minorUnits)
    }

    func testOnlyThisMonthsBazarAndMealsCount() throws {
        var rent = try Expense(groupID: GroupID(), title: "Rent", total: Money(minorUnits: 9000_00), paidBy: [a: Money(minorUnits: 9000_00)],
                               splitRule: .equal([a, b, c]), occurredAt: date(1), category: .rent)
        rent.note = nil
        let expenses = [try bazar(500, paidBy: a, on: 5), try bazar(800, paidBy: a, on: 30, month: 10), rent]
        let counts = [try meals(a, 2, on: 5), try meals(b, 2, on: 31, month: 10)]
        let summary = try MessMonthSummary(month: november, members: [a, b, c], meals: counts, expenses: expenses, currency: .bdt, calendar: calendar)
        XCTAssertEqual(summary.bazarTotal.minorUnits, 500_00)
        XCTAssertEqual(summary.halfMeals[b], 0)
        XCTAssertEqual(summary.bazarExpenses.count, 1)
    }

    func testNoMealsMeansNoRateAndNoSplit() throws {
        let summary = try MessMonthSummary(month: november, members: [a, b], meals: [], expenses: [try bazar(100, paidBy: a, on: 1)],
                                           currency: .bdt, calendar: calendar)
        XCTAssertNil(summary.mealRate)
        XCTAssertNil(summary.mealSplitRule)
    }

    func testMealDayAndMonthText() throws {
        XCTAssertEqual(MealDay("2026-11-05"), day(5))
        XCTAssertNil(MealDay("2026-02-30"))
        XCTAssertEqual(november.description, "2026-11")
        XCTAssertEqual(november.next().description, "2026-12")
        XCTAssertEqual(MessMonth(year: 2026, month: 1)!.previous().description, "2025-12")
        XCTAssertThrowsError(try MealCount(memberID: a, day: day(1), halfMeals: -1))
    }
}
