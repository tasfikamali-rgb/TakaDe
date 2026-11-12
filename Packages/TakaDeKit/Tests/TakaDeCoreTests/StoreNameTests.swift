import XCTest
@testable import TakaDeCore

final class StoreNameTests: XCTestCase {
    func testTrimsCollapsesSpacesAndLowercases() {
        XCTAssertEqual(StoreName.normalized("  SHWAPNO   Super\nShop "), "shwapno super shop")
    }

    func testKeepsBanglaNames() {
        XCTAssertEqual(StoreName.normalized(" স্বপ্ন "), "স্বপ্ন")
    }

    func testRejectsNothingWorthCounting() {
        XCTAssertNil(StoreName.normalized(nil))
        XCTAssertNil(StoreName.normalized("   "))
        XCTAssertNil(StoreName.normalized("A"))
        XCTAssertNil(StoreName.normalized("01712 345678"))
        XCTAssertNil(StoreName.normalized(String(repeating: "a", count: 61)))
    }

    func testSixtyCharactersIsFine() {
        XCTAssertEqual(StoreName.normalized(String(repeating: "a", count: 60))?.count, 60)
    }

    func testCountryCode() {
        XCTAssertEqual(StoreName.countryCode("BD"), "BD")
        XCTAssertEqual(StoreName.countryCode("other"), "ZZ")
        XCTAssertEqual(StoreName.countryCode(nil), "ZZ")
        XCTAssertEqual(StoreName.countryCode("bd"), "ZZ")
    }
}
