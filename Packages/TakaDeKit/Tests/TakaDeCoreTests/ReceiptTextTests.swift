#if canImport(Compression)
import Foundation
import XCTest
@testable import TakaDeCore

final class ReceiptTextTests: XCTestCase {
    private let receipt = [
        "STAR KABAB & RESTAURANT", "Dhanmondi, Dhaka", "Date: 10/11/2026",
        "Chicken Biryani  2 x 350.00   700.00", "Borhani         2 x 80.00    160.00",
        "মিষ্টি দই                      120.00", "Subtotal                     980.00",
        "VAT 7.5%                      73.50", "TOTAL                       1053.50", "Thank you!",
    ]

    func testRoundTripKeepsEveryLineExactly() throws {
        XCTAssertEqual(try ReceiptText.unpack(try ReceiptText.pack(receipt)), receipt)
    }

    func testPackedTextIsTinyNextToAPhoto() throws {
        let long = Array(repeating: receipt, count: 6).flatMap { $0 }
        // A receipt photo is 60 to 180 KB; 60 lines of its text should stay around 1 KB.
        XCTAssertLessThan(try ReceiptText.pack(long).count, 2_000)
    }

    func testCleanDropsBlankLinesAndCapsSizes() {
        XCTAssertEqual(ReceiptText.clean(["  Rice ", "", "   ", "Total 100"]), ["Rice", "Total 100"])
        XCTAssertEqual(ReceiptText.clean(Array(repeating: "x", count: 1_000)).count, ReceiptText.maxLines)
        XCTAssertEqual(ReceiptText.clean([String(repeating: "a", count: 5_000)]).first?.count, ReceiptText.maxLineLength)
    }

    func testAnEmptyReceiptStillTravels() throws {
        XCTAssertEqual(try ReceiptText.unpack(try ReceiptText.pack([])), [])
    }

    func testRejectsTooManyLinesFromAnotherPhone() throws {
        let json = try JSONEncoder().encode(["lines": Array(repeating: "x", count: ReceiptText.maxLines + 1)])
        let versioned = Data(String(decoding: json, as: UTF8.self).replacingOccurrences(of: "{", with: #"{"v":1,"#).utf8)
        XCTAssertThrowsError(try ReceiptText.decode(versioned))
    }

    func testRejectsOverlongLinesUnknownVersionsAndJunk() throws {
        let long = String(repeating: "a", count: ReceiptText.maxLineLength + 1)
        XCTAssertThrowsError(try ReceiptText.decode(Data(#"{"v":1,"lines":["\#(long)"]}"#.utf8)))
        XCTAssertThrowsError(try ReceiptText.decode(Data(#"{"v":2,"lines":["a"]}"#.utf8)))
        XCTAssertThrowsError(try ReceiptText.unpack(Data("not compressed".utf8)))
    }

    func testRefusesSomethingThatInflatesPastTheLimit() throws {
        let bomb = try (Data(count: 5_000_000) as NSData).compressed(using: .zlib) as Data
        XCTAssertThrowsError(try ReceiptText.unpack(bomb))
    }
}
#endif
