import XCTest
@testable import TakaDeCore

final class PaymentHandleTests: XCTestCase {
    func testWalletNumbersNormalize() {
        XCTAssertEqual(PaymentHandle.walletNumber(from: "01712345678"), "01712345678")
        XCTAssertEqual(PaymentHandle.walletNumber(from: "+880 1712-345678"), "01712345678")
        XCTAssertEqual(PaymentHandle.walletNumber(from: "০১৭১২৩৪৫৬৭৮"), "01712345678")
    }

    func testRejectsWhatIsNotABangladeshiMobile() {
        XCTAssertNil(PaymentHandle.walletNumber(from: "1234"))           // a PIN-length number
        XCTAssertNil(PaymentHandle.walletNumber(from: "01212345678"))    // no 012 operator
        XCTAssertNil(PaymentHandle.walletNumber(from: "017123456789"))   // too long
        XCTAssertThrowsError(try PaymentHandle(memberID: MemberID(), rail: .bkash, handle: "12345"))
    }

    func testBankDetailsAreKeptAsTyped() throws {
        let handle = try PaymentHandle(memberID: MemberID(), rail: .bank, handle: "  DBBL · A/C ending 4821 ", label: "")
        XCTAssertEqual(handle.handle, "DBBL · A/C ending 4821")
        XCTAssertNil(handle.label)
        XCTAssertThrowsError(try PaymentHandle(memberID: MemberID(), rail: .bank, handle: "   "))
    }
}
