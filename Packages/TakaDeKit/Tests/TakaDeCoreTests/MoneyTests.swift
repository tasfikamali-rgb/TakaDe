import XCTest
@testable import TakaDeCore

final class MoneyTests: XCTestCase {
    func testParsesLatinAndBengaliDigits() throws {
        XCTAssertEqual(try Money.parse("1,250.5").minorUnits, 125_050)
        XCTAssertEqual(try Money.parse("১২৫০.৫০").minorUnits, 125_050)
        XCTAssertEqual(try Money.parse("৳ 0.07").minorUnits, 7)
        XCTAssertEqual(try Money.parse(".5").minorUnits, 50)
        XCTAssertEqual(try Money.parse("-3").minorUnits, -300)
    }

    func testRejectsAmbiguousInput() {
        XCTAssertThrowsError(try Money.parse(""))
        XCTAssertThrowsError(try Money.parse("1.005"), "more decimals than BDT allows must not be silently rounded")
        XCTAssertThrowsError(try Money.parse("1.2.3"))
        XCTAssertThrowsError(try Money.parse("12a"))
        XCTAssertThrowsError(try Money.parse("99999999999999999999"))
    }

    func testArithmeticDetectsOverflowAndCurrencyMismatch() {
        let max = Money(minorUnits: .max)
        XCTAssertThrowsError(try max.adding(Money(minorUnits: 1)))
        let usd = Money(minorUnits: 1, currency: Currency(code: "USD", minorUnitDigits: 2))
        XCTAssertThrowsError(try Money(minorUnits: 1).adding(usd))
    }

    func testFormatting() {
        let m = Money(minorUnits: 785_443)
        XCTAssertEqual(MoneyFormatter.format(m).plain, "৳\u{00A0}7,854.43")
        let bn = MoneyFormatter.format(m, digits: .bengali)
        XCTAssertEqual(bn.whole, "৭,৮৫৪")
        XCTAssertEqual(bn.fraction, ".৪৩")
        XCTAssertEqual(MoneyFormatter.format(Money(minorUnits: -5)).plain, "\u{2212}৳\u{00A0}0.05")
        XCTAssertEqual(MoneyFormatter.format(Money(minorUnits: 100_000), showsZeroFraction: false).plain, "৳\u{00A0}1,000")
    }

    func testDigitConversionLeavesOtherTextAlone() {
        XCTAssertEqual(Digits.toBengali("Rishan 42"), "Rishan ৪২")
        XCTAssertEqual(Digits.toLatin("রিশান ৪২"), "রিশান 42")
    }
}
