import XCTest
@testable import TakaDeCore

final class ExchangeRatesTests: XCTestCase {
    private let gbp = Currency(code: "GBP", minorUnitDigits: 2)
    private let jpy = Currency(code: "JPY", minorUnitDigits: 0)
    private let kwd = Currency(code: "KWD", minorUnitDigits: 3)

    /// Same shape as the real download, trimmed (rates per 1 BDT on 2026-11-11).
    private let sample = Data("""
    {"date":"2026-11-11","bdt":{"bdt":1,"usd":0.007997146,"gbp":0.0059913807,"jpy":1.26993896,\
    "kwd":0.0024874889,"btc":1.0846672e-7,"xau":0.0000019696171,"dem":0.0139,"bad":"x","neg":-2,"zero":0}}
    """.utf8)

    func testParsesTableAndDropsJunk() throws {
        let rates = try ExchangeRates.parse(sample, base: "BDT")
        XCTAssertEqual(rates.base, "BDT")
        XCTAssertEqual(rates.date, "2026-11-11")
        XCTAssertEqual(rates.rates["BDT"], 1)
        XCTAssertNotNil(rates.rates["GBP"])
        XCTAssertNotNil(rates.rates["BTC"], "Kept in the table; the picker filters it out")
        XCTAssertNil(rates.rates["BAD"])
        XCTAssertNil(rates.rates["NEG"])
        XCTAssertNil(rates.rates["ZERO"])
    }

    func testPickerListsOnlyKnownISOCurrenciesWithoutBase() throws {
        let rates = try ExchangeRates.parse(sample, base: "BDT")
        let known: Set<String> = ["BDT", "USD", "GBP", "JPY", "KWD", "XAU"]
        XCTAssertEqual(rates.currencyCodes(knownISO: known), ["GBP", "JPY", "KWD", "USD"])
    }

    func testRejectsBadDownloads() {
        XCTAssertThrowsError(try ExchangeRates.parse(Data("not json".utf8), base: "BDT"))
        XCTAssertThrowsError(try ExchangeRates.parse(Data(#"{"bdt":{"usd":0.008}}"#.utf8), base: "BDT"))
        XCTAssertThrowsError(try ExchangeRates.parse(Data(#"{"date":"yesterday","bdt":{"usd":0.008}}"#.utf8), base: "BDT"))
        XCTAssertThrowsError(try ExchangeRates.parse(Data(#"{"date":"2026-11-11","eur":{"usd":1.1}}"#.utf8), base: "BDT"))
        XCTAssertThrowsError(try ExchangeRates.parse(Data(#"{"date":"2026-11-11","bdt":{"usd":"x"}}"#.utf8), base: "BDT"))
        let huge = Data(repeating: 0x20, count: ExchangeRates.maxBytes + 1)
        XCTAssertThrowsError(try ExchangeRates.parse(huge, base: "BDT")) { error in
            XCTAssertEqual(error as? ExchangeRates.ParseError, .tooLarge)
        }
    }

    func testConvertsTakaToPoundsRoundingToPence() throws {
        let rates = ExchangeRates(base: "BDT", date: "2026-11-11", rates: ["BDT": 1, "GBP": Decimal(string: "0.006")!])
        // ৳1,000.00 x 0.006 = £6.00
        XCTAssertEqual(rates.convert(Money(minorUnits: 100_000), to: gbp), Money(minorUnits: 600, currency: gbp))
        // ৳12.34 x 0.006 = £0.07404 -> £0.07
        XCTAssertEqual(rates.convert(Money(minorUnits: 1_234), to: gbp), Money(minorUnits: 7, currency: gbp))
        // ৳12.50 x 0.006 = £0.075 -> £0.08 (half away from zero)
        XCTAssertEqual(rates.convert(Money(minorUnits: 1_250), to: gbp), Money(minorUnits: 8, currency: gbp))
        XCTAssertEqual(rates.convert(Money(minorUnits: -1_250), to: gbp), Money(minorUnits: -8, currency: gbp))
        XCTAssertEqual(rates.convert(.zero(), to: gbp), Money.zero(gbp))
    }

    func testRespectsTargetMinorUnits() throws {
        let rates = try ExchangeRates.parse(sample, base: "BDT")
        // ৳1,000 -> about ¥1,270 (no decimals) and about KD 2.487 (three decimals)
        XCTAssertEqual(rates.convert(Money(minorUnits: 100_000), to: jpy), Money(minorUnits: 1_270, currency: jpy))
        XCTAssertEqual(rates.convert(Money(minorUnits: 100_000), to: kwd), Money(minorUnits: 2_487, currency: kwd))
    }

    func testCrossRateThroughBase() throws {
        let rates = ExchangeRates(base: "BDT", date: "2026-11-11",
                                  rates: ["BDT": 1, "USD": Decimal(string: "0.008")!, "GBP": Decimal(string: "0.006")!])
        let usd = Currency(code: "USD", minorUnitDigits: 2)
        // $8.00 = ৳1,000 = £6.00
        XCTAssertEqual(rates.convert(Money(minorUnits: 800, currency: usd), to: gbp), Money(minorUnits: 600, currency: gbp))
        XCTAssertEqual(rates.rate(from: "GBP", to: "BDT").map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
                       166.666, accuracy: 0.001)
    }

    func testSameCurrencyIsUnchangedAndMissingRateIsNil() {
        let rates = ExchangeRates(base: "BDT", date: "2026-11-11", rates: ["BDT": 1])
        XCTAssertEqual(rates.convert(Money(minorUnits: 4_321), to: .bdt), Money(minorUnits: 4_321))
        XCTAssertNil(rates.convert(Money(minorUnits: 4_321), to: gbp))
    }

    func testHugeAmountsDoNotOverflowSilently() {
        let rates = ExchangeRates(base: "BDT", date: "2026-11-11", rates: ["BDT": 1, "JPY": 1_000_000])
        XCTAssertNil(rates.convert(Money(minorUnits: .max), to: jpy))
    }

    func testRoundTripsThroughCodable() throws {
        let rates = try ExchangeRates.parse(sample, base: "BDT")
        let copy = try JSONDecoder().decode(ExchangeRates.self, from: JSONEncoder().encode(rates))
        XCTAssertEqual(copy.date, rates.date)
        XCTAssertEqual(Set(copy.rates.keys), Set(rates.rates.keys))
        XCTAssertEqual(copy.convert(Money(minorUnits: 100_000), to: gbp), rates.convert(Money(minorUnits: 100_000), to: gbp))
    }
}
