import XCTest
@testable import TakaDeCore

final class FriendCodeTests: XCTestCase {
    func testFormatsAndReadsBack() throws {
        let code = try XCTUnwrap(FriendCode(raw: "7F3K9QXM"))
        XCTAssertEqual(code.description, "TKD-7F3K-9QXM")
        XCTAssertEqual(FriendCode(typed: code.description), code)
        XCTAssertEqual(FriendCode(scanned: code.url.absoluteString), code)
    }

    func testTypedLeniently() {
        let expected = FriendCode(raw: "7F3K9QX1")
        XCTAssertEqual(FriendCode(typed: "tkd-7f3k-9qxl"), expected)
        XCTAssertEqual(FriendCode(typed: " 7F3K 9QXI "), expected)
        XCTAssertEqual(FriendCode(typed: "TKD7F3K9QX1"), expected)
        XCTAssertEqual(FriendCode(typed: "7f3k-9qxl"), expected)
        XCTAssertEqual(FriendCode(typed: "0O0O0O0O"), FriendCode(raw: "00000000"))
    }

    func testRejectsAnythingElse() {
        XCTAssertNil(FriendCode(typed: ""))
        XCTAssertNil(FriendCode(typed: "hello"))
        XCTAssertNil(FriendCode(typed: "7F3K9QX"))
        XCTAssertNil(FriendCode(typed: "7F3K9QXMM"))
        XCTAssertNil(FriendCode(typed: "7F3K9QXU"))
        XCTAssertNil(FriendCode(typed: "7F3K-9QX!"))
        XCTAssertNil(FriendCode(scanned: "https://example.com/?c=7F3K9QXM"))
        XCTAssertNil(FriendCode(scanned: "takade://join?c=7F3K9QXM"))
    }

    func testRandomUsesAllFortyBits() {
        XCTAssertEqual(FriendCode(randomBytes: [0, 0, 0, 0, 0]).raw, "00000000")
        XCTAssertEqual(FriendCode(randomBytes: [255, 255, 255, 255, 255]).raw, "ZZZZZZZZ")
        XCTAssertEqual(FriendCode(randomBytes: [0, 0, 0, 0, 1]).raw, "00000001")
        XCTAssertEqual(FriendCode(randomBytes: [0x80, 0, 0, 0, 0]).raw, "G0000000")
        for _ in 0..<50 {
            let bytes = (0..<5).map { _ in UInt8.random(in: 0...255) }
            XCTAssertNotNil(FriendCode(raw: FriendCode(randomBytes: bytes).raw))
        }
    }
}
