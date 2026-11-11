import XCTest
@testable import TakaDeCore

final class SplitTests: XCTestCase {
    let a = MemberID(), b = MemberID(), c = MemberID()

    func testEqualSplitDistributesRemainderDeterministically() throws {
        let alloc = try SplitCalculator.allocate(Money(minorUnits: 100), by: .equal([a, b, c]))
        XCTAssertEqual(alloc.shares[a]?.minorUnits, 34)
        XCTAssertEqual(alloc.shares[b]?.minorUnits, 33)
        XCTAssertEqual(alloc.shares[c]?.minorUnits, 33)
        XCTAssertEqual(try alloc.total(in: .bdt).minorUnits, 100)
    }

    func testEqualSplitIgnoresDuplicates() throws {
        let alloc = try SplitCalculator.allocate(Money(minorUnits: 1000), by: .equal([a, a, b]))
        XCTAssertEqual(alloc.shares.count, 2)
        XCTAssertEqual(alloc.shares[a]?.minorUnits, 500)
    }

    func testSplitsAlwaysSumToTotal() throws {
        for total in [1, 2, 7, 99, 100, 101, 12_345, 1_000_003] as [Int64] {
            for rule in [SplitRule.equal([a, b, c]), .shares([a: 2, b: 1, c: 4]), .percentage([a: 3333, b: 3333, c: 3334])] {
                let alloc = try SplitCalculator.allocate(Money(minorUnits: total), by: rule)
                XCTAssertEqual(try alloc.total(in: .bdt).minorUnits, total, "\(rule) at \(total)")
                XCTAssertTrue(alloc.shares.values.allSatisfy { $0.minorUnits >= 0 })
            }
        }
    }

    func testSharesSplit() throws {
        let alloc = try SplitCalculator.allocate(Money(minorUnits: 90_000), by: .shares([a: 2, b: 1]))
        XCTAssertEqual(alloc.shares[a]?.minorUnits, 60_000)
        XCTAssertEqual(alloc.shares[b]?.minorUnits, 30_000)
    }

    func testExactSplitMustMatchTotal() {
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: 1000), by: .exact([a: Money(minorUnits: 400), b: Money(minorUnits: 500)]))) { error in
            XCTAssertEqual(error as? SplitError, .exactAmountsDoNotMatchTotal(expected: Money(minorUnits: 1000), actual: Money(minorUnits: 900)))
        }
    }

    func testPercentagesMustSumTo100() {
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: 1000), by: .percentage([a: 5000, b: 4000])))
    }

    func testRejectsZeroAndEmpty() {
        XCTAssertThrowsError(try SplitCalculator.allocate(.zero(), by: .equal([a])))
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: 10), by: .equal([])))
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: 10), by: .shares([a: 0])))
    }

    func testOverflowIsReportedNotWrapped() {
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: .max / 2), by: .shares([a: 4, b: 1])))
    }

    // MARK: Adjusted

    func testAdjustedAddsExtraOnTopOfEqualSplit() throws {
        // 1,050 dinner, A had a 150 drink: 900 split three ways, then +150 for A.
        let rule = SplitRule.adjusted([a: Money(minorUnits: 150_00), b: .zero(), c: .zero()])
        let alloc = try SplitCalculator.allocate(Money(minorUnits: 1_050_00), by: rule)
        XCTAssertEqual(alloc.shares[a]?.minorUnits, 450_00)
        XCTAssertEqual(alloc.shares[b]?.minorUnits, 300_00)
        XCTAssertEqual(alloc.shares[c]?.minorUnits, 300_00)
    }

    func testAdjustedAllowsMinus() throws {
        // C skipped dessert: 60 less for C.
        let rule = SplitRule.adjusted([a: .zero(), b: .zero(), c: Money(minorUnits: -60_00)])
        let alloc = try SplitCalculator.allocate(Money(minorUnits: 600_00), by: rule)
        XCTAssertEqual(alloc.shares[a]?.minorUnits, 220_00)
        XCTAssertEqual(alloc.shares[b]?.minorUnits, 220_00)
        XCTAssertEqual(alloc.shares[c]?.minorUnits, 160_00)
    }

    func testAdjustedAlwaysSumsToTotal() throws {
        // Totals large enough that nobody's equal part is smaller than the minus.
        for total in [7, 100, 101, 12_345, 1_000_003] as [Int64] {
            let rule = SplitRule.adjusted([a: Money(minorUnits: 1), b: .zero(), c: Money(minorUnits: -1)])
            let alloc = try SplitCalculator.allocate(Money(minorUnits: total), by: rule)
            XCTAssertEqual(try alloc.total(in: .bdt).minorUnits, total)
        }
    }

    func testAdjustmentsLargerThanTotalAreRejected() {
        let rule = SplitRule.adjusted([a: Money(minorUnits: 500), b: .zero()])
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: 400), by: rule)) { error in
            XCTAssertEqual(error as? SplitError, .adjustmentsExceedTotal(total: Money(minorUnits: 400), adjustments: Money(minorUnits: 500)))
        }
    }

    func testMinusLargerThanEqualPartIsRejected() {
        let rule = SplitRule.adjusted([a: .zero(), b: Money(minorUnits: -300)])
        XCTAssertThrowsError(try SplitCalculator.allocate(Money(minorUnits: 200), by: rule)) { error in
            XCTAssertEqual(error as? SplitError, .negativeAmount(b))
        }
    }

    func testAdjustedRuleRoundTripsThroughCodable() throws {
        let rule = SplitRule.adjusted([a: Money(minorUnits: 150_00), b: .zero()])
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(SplitRule.self, from: data), rule)
    }
}
