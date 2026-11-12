import XCTest
@testable import TakaDeCore

final class EditSummaryTests: XCTestCase {
    let a = MemberID(), b = MemberID(), c = MemberID()
    let group = GroupID()

    private func expense(_ title: String = "Dinner", total: Int64 = 50_000, paidBy payer: MemberID? = nil,
                         rule: SplitRule? = nil, on date: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> Expense {
        let payer = payer ?? a
        return try Expense(id: ExpenseID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), groupID: group, title: title,
                           total: Money(minorUnits: total), paidBy: [payer: Money(minorUnits: total)],
                           splitRule: rule ?? .equal([a, b]), occurredAt: date)
    }

    func testAmountChangeIsTheOnlyChangeWhenTheEqualSplitStays() throws {
        let old = try expense(total: 50_000), new = try expense(total: 65_000)
        XCTAssertEqual(ExpenseChange.between(old, new), [.total(from: Money(minorUnits: 50_000), to: Money(minorUnits: 65_000))])
    }

    func testTitlePayerAndSplit() throws {
        let old = try expense()
        let new = try expense("Lunch", paidBy: b, rule: .equal([a, b, c]))
        XCTAssertEqual(ExpenseChange.between(old, new), [.title(from: "Dinner", to: "Lunch"), .paidBy, .split])
    }

    func testExactAmountsFollowingTheTotalAreNotASplitChange() throws {
        let old = try expense(total: 300, rule: .exact([a: Money(minorUnits: 100), b: Money(minorUnits: 200)]))
        let new = try expense(total: 400, rule: .exact([a: Money(minorUnits: 100), b: Money(minorUnits: 300)]))
        XCTAssertEqual(ExpenseChange.between(old, new), [.total(from: Money(minorUnits: 300), to: Money(minorUnits: 400))])
        let moved = try expense(total: 300, rule: .exact([a: Money(minorUnits: 150), b: Money(minorUnits: 150)]))
        XCTAssertEqual(ExpenseChange.between(old, moved), [.split])
    }

    func testSameDayIsNotADateChange() throws {
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let old = try expense(on: morning), later = try expense(on: morning.addingTimeInterval(60))
        XCTAssertEqual(ExpenseChange.between(old, later, calendar: utc), [])
        let nextWeek = try expense(on: morning.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(ExpenseChange.between(old, nextWeek, calendar: utc).count, 1)
    }

    func testDeleteAloneChangesNothingVisible() throws {
        let old = try expense()
        var deleted = old
        deleted.deletedAt = Date()
        deleted.version += 1
        XCTAssertEqual(ExpenseChange.between(old, deleted), [])
    }

    func testSettlementChanges() throws {
        let old = try Settlement(groupID: group, from: a, to: b, amount: Money(minorUnits: 50_000), method: .cash)
        var new = old
        try new.edit(amount: Money(minorUnits: 40_000), method: .bkash, userReference: "8N7A", by: a)
        XCTAssertEqual(SettlementChange.between(old, new), [
            .amount(from: Money(minorUnits: 50_000), to: Money(minorUnits: 40_000)),
            .method(from: .cash, to: .bkash),
            .reference,
        ])
    }

    func testOnlyTheRecipientChangesAnAcknowledgedAmount() throws {
        var s = try Settlement(groupID: group, from: a, to: b, amount: Money(minorUnits: 50_000), method: .cash)
        try s.acknowledge(by: b)
        XCTAssertThrowsError(try s.edit(amount: Money(minorUnits: 10_000), method: .cash, userReference: nil, by: a)) {
            XCTAssertEqual($0 as? LedgerError, .settlementAmountLocked)
        }
        // The payer can still fix the method or transaction id.
        XCTAssertNoThrow(try s.edit(amount: Money(minorUnits: 50_000), method: .bkash, userReference: "X1", by: a))
        XCTAssertNoThrow(try s.edit(amount: Money(minorUnits: 45_000), method: .bkash, userReference: "X1", by: b))
        XCTAssertEqual(s.amount, Money(minorUnits: 45_000))
        XCTAssertThrowsError(try s.edit(amount: .zero(), method: .cash, userReference: nil, by: b))
    }

    func testOlderPaymentsDecodeWithoutChangedBy() throws {
        let s = try Settlement(groupID: group, from: a, to: b, amount: Money(minorUnits: 100), method: .cash)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json.removeValue(forKey: "changedBy")
        let decoded = try JSONDecoder().decode(Settlement.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.changedBy)
    }
}
