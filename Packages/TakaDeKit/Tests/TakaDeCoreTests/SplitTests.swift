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
}
