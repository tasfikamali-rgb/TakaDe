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

    func testWithoutTotalLineUsesSumOfItemsWithLowConfidence() {
        let s = ReceiptParser.parse(lines: ["Corner Shop", "Tea 20", "Cake 150"])
        XCTAssertEqual(s.total?.minorUnits, 170_00)
        XCTAssertTrue(s.candidateAmounts.contains(Money(minorUnits: 170_00)))
        XCTAssertLessThan(s.confidence, 0.8)
    }

    func testFallsBackToLargestAmountWithLowConfidence() {
        let s = ReceiptParser.parse(lines: ["Corner Shop", "Paid 150"])
        XCTAssertEqual(s.total?.minorUnits, 150_00)
        XCTAssertLessThan(s.confidence, 0.5)
    }

    func testItemWordsAreNotMistakenForHeadings() {
        let s = ReceiptParser.parse(lines: ["Green Bowl", "Tax Invoice", "Mixed Vegetable 220", "Chicken Biryani 300", "Total 520"])
        XCTAssertEqual(s.items.map(\.label), ["Mixed Vegetable", "Chicken Biryani"])
        XCTAssertTrue(s.charges.isEmpty)
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

    func testReadsItemsAndCharges() {
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
        XCTAssertEqual(s.items.map(\.label), ["Kacchi Biryani", "Borhani"])
        XCTAssertEqual(s.items.map(\.amount.minorUnits), [640_00, 120_00])
        XCTAssertEqual(s.charges.map(\.kind), [.subtotal, .tax])
        XCTAssertEqual(s.charges.map(\.amount.minorUnits), [760_00, 38_00])
        XCTAssertEqual(s.computedTotal?.minorUnits, 798_00)
        XCTAssertEqual(s.computedTotal, s.total)
    }

    func testServiceChargeAndDiscountWithoutSubtotal() {
        let lines = [
            "Cafe Mango",
            "Gulshan 2",
            "2x Cappuccino 480",
            "Cheesecake 350",
            "Service Charge 10% 83",
            "Discount -50",
            "Total 863",
        ]
        let s = ReceiptParser.parse(lines: lines)
        XCTAssertEqual(s.items.map(\.label), ["Cappuccino", "Cheesecake"])
        XCTAssertEqual(s.charges.map(\.kind), [.serviceCharge, .discount])
        XCTAssertEqual(s.charges.last?.amount.minorUnits, 50_00)
        XCTAssertEqual(s.computedTotal?.minorUnits, 863_00)
        XCTAssertEqual(s.total?.minorUnits, 863_00)
    }

    func testMismatchIsVisible() {
        // OCR misread 120 as 170.
        let s = ReceiptParser.parse(lines: ["Shop", "Area", "Rice 170", "Dal 80", "Total 200"])
        XCTAssertEqual(s.computedTotal?.minorUnits, 250_00)
        XCTAssertNotEqual(s.computedTotal, s.total)
    }

    func testNoItemsWhenNothingIsPriced() {
        let s = ReceiptParser.parse(lines: ["Shwapno", "মোট", "১,২৫০.৫০"])
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertNil(s.computedTotal)
    }

    // MARK: Dates (synthetic lines)

    private func ymd(_ lines: [String]) -> [Int]? {
        ReceiptParser.date(in: lines).map {
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: $0)
            return [c.year!, c.month!, c.day!]
        }
    }

    func testReadsCommonReceiptDateFormats() {
        XCTAssertEqual(ymd(["Date: 05/11/2026"]), [2026, 11, 5])
        XCTAssertEqual(ymd(["05-11-26 18:42"]), [2026, 11, 5])
        XCTAssertEqual(ymd(["2026-11-05 18:42:10"]), [2026, 11, 5])
        XCTAssertEqual(ymd(["Date 05-Nov-2026"]), [2026, 11, 5])
        XCTAssertEqual(ymd(["5 November 2026"]), [2026, 11, 5])
        XCTAssertEqual(ymd(["Nov 5, 2026  7:10 PM"]), [2026, 11, 5])
        XCTAssertEqual(ymd(["তারিখ: ০৫/১১/২০২৬"]), [2026, 11, 5])
    }

    func testIgnoresThingsThatAreNotDates() {
        XCTAssertNil(ymd(["Tel 01711-223344", "Time 12.30", "Invoice 2026-99"]))
        XCTAssertNil(ymd(["31/02/2026"]))
        XCTAssertNil(ymd(["12/10/1987"]))
    }

    func testSkipsDatesAfterToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 23))!
        func read(_ lines: [String]) -> [Int]? {
            ReceiptParser.date(in: lines, now: now).map {
                let c = calendar.dateComponents([.year, .month, .day], from: $0)
                return [c.year!, c.month!, c.day!]
            }
        }
        // Today is fine; tomorrow isn't.
        XCTAssertEqual(read(["12/11/2026"]), [2026, 11, 12])
        XCTAssertNil(read(["13/11/2026"]))
        XCTAssertNil(read(["2027-01-05"]))
        // A later date on the slip is passed over for the real one below it.
        XCTAssertEqual(read(["Valid till 05/11/2027", "Date: 05/11/2026"]), [2026, 11, 5])
    }

    func testIsoDateIsNotMisreadAsDayFirst() {
        // "2026-11-05" also contains "26-11-05"; it must read as 5 November 2026.
        XCTAssertEqual(ymd(["2026-11-05"]), [2026, 11, 5])
    }
}
