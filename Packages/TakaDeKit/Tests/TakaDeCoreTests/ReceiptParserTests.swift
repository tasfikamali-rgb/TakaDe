import XCTest
@testable import TakaDeCore

/// Synthetic receipts only. Never add real customer receipts to tests.
final class ReceiptParserTests: XCTestCase {
    func testFindsLabelledTotalNotSubtotal() {
        let lines = [
            "Star Kabab & Restaurant",
            "Dhanmondi, Dhaka",
            "Date: 05/11/2026",
            "Kacchi Biryani   2   640.00",
            "Borhani          2   120.00",
            "Sub Total            760.00",
            "VAT 5%                38.00",
            "Grand Total          798.00",
            "Cash                1000.00",
            "Change               202.00",
        ]
        let s = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(s.total?.minorUnits, 798_00)
        XCTAssertEqual(s.merchant, "Star Kabab & Restaurant")
        XCTAssertGreaterThanOrEqual(s.confidence, 0.8)
        let parts = s.date.map { Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: $0) }
        XCTAssertEqual(parts?.day, 5)
        XCTAssertEqual(parts?.month, 11)
        XCTAssertEqual(parts?.year, 2026)
    }

    func testTotalOnFollowingLineAndBengaliDigits() {
        let s = ReceiptParser.parse(lines: ["Shwapno", "মোট", "১,২৫০.৫০"])
        XCTAssertEqual(s.total?.minorUnits, 1250_50)
    }

    func testFallsBackToLargestAmountWithLowConfidence() {
        let s = ReceiptParser.parse(lines: ["Corner Shop", "Tea 20", "Cake 150"])
        XCTAssertEqual(s.total?.minorUnits, 150_00)
        XCTAssertLessThan(s.confidence, 0.5)
    }

    func testIgnoresPhoneNumbersAndDates() {
        let amounts = ReceiptParser.amountsIn("Tel: 01712-345678 on 12/10/2026", currency: .bdt)
        XCTAssertTrue(amounts.isEmpty, "\(amounts)")
    }

    func testEmptyInput() {
        let s = ReceiptParser.parse(lines: [])
        XCTAssertNil(s.total)
        XCTAssertEqual(s.confidence, 0)
    }
}
