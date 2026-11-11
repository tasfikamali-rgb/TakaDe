import XCTest
@testable import TakaDeCore

/// Synthetic data only.
final class MonthlyRepeatTests: XCTestCase {
    let a = MemberID(), b = MemberID()
    let group = GroupID()
    var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return cal
    }()

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    func rent(on date: Date, repeats: Bool = true) throws -> Expense {
        try Expense(groupID: group, title: "Rent", total: Money(minorUnits: 12000_00), paidBy: [a: Money(minorUnits: 12000_00)],
                    splitRule: .equal([a, b]), occurredAt: date, category: .rent, repeatsMonthly: repeats)
    }

    func testAddsOneCopyPerMonthUpToNow() throws {
        let source = try rent(on: date(2026, 9, 5))
        let copies = MonthlyRepeat.dueCopies(of: [source], now: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(copies.map { calendar.component(.month, from: $0.occurredAt) }, [10, 11])
        XCTAssertTrue(copies.allSatisfy { $0.repeatOf == source.id && !$0.repeatsMonthly && $0.total == source.total })
        XCTAssertTrue(copies.allSatisfy { $0.allocation == source.allocation })
    }

    func testWaitsForTheDayOfTheMonth() throws {
        let source = try rent(on: date(2026, 10, 20))
        XCTAssertTrue(MonthlyRepeat.dueCopies(of: [source], now: date(2026, 11, 19), calendar: calendar).isEmpty)
        XCTAssertEqual(MonthlyRepeat.dueCopies(of: [source], now: date(2026, 11, 21), calendar: calendar).count, 1)
    }

    func testExistingOrDeletedCopiesAreNotAddedAgain() throws {
        let source = try rent(on: date(2026, 9, 5))
        var october = try XCTUnwrap(MonthlyRepeat.dueCopies(of: [source], now: date(2026, 10, 6), calendar: calendar).first)
        october.deletedAt = date(2026, 10, 7)
        let copies = MonthlyRepeat.dueCopies(of: [source, october], now: date(2026, 11, 6), calendar: calendar)
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(calendar.component(.month, from: copies[0].occurredAt), 11)
    }

    func testStopsWhenTurnedOffOrDeleted() throws {
        let off = try rent(on: date(2026, 9, 5), repeats: false)
        var deleted = try rent(on: date(2026, 9, 5))
        deleted.deletedAt = date(2026, 9, 6)
        XCTAssertTrue(MonthlyRepeat.dueCopies(of: [off, deleted], now: date(2026, 11, 6), calendar: calendar).isEmpty)
    }

    func testDayThirtyOneMovesToTheEndOfShortMonths() throws {
        let source = try rent(on: date(2026, 10, 31))
        let copies = MonthlyRepeat.dueCopies(of: [source], now: date(2027, 3, 1), calendar: calendar)
        XCTAssertEqual(copies.map { calendar.component(.day, from: $0.occurredAt) }, [30, 31, 31, 28])
    }

    func testCatchUpIsCapped() throws {
        let source = try rent(on: date(2020, 1, 1))
        XCTAssertEqual(MonthlyRepeat.dueCopies(of: [source], now: date(2026, 11, 2), calendar: calendar).count, MonthlyRepeat.maxCatchUpMonths)
    }

    func testOldExpenseJSONDecodesAsNotRepeating() throws {
        let expense = try rent(on: date(2026, 9, 5))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(expense)) as! [String: Any]
        json.removeValue(forKey: "repeatsMonthly")
        json.removeValue(forKey: "repeatOf")
        let decoded = try JSONDecoder().decode(Expense.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.repeatsMonthly)
        XCTAssertNil(decoded.repeatOf)
        XCTAssertEqual(decoded.allocation, expense.allocation)
    }
}
