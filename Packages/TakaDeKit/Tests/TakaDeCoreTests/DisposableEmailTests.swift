import XCTest
@testable import TakaDeCore

final class DisposableEmailTests: XCTestCase {
    func testBundledListBlocksCommonThrowawayProviders() {
        let check = DisposableEmail.bundled
        for email in ["a@10minutemail.com", "a@mailinator.com", "a@yopmail.com", "a@guerrillamail.com", "a@temp-mail.org"] {
            XCTAssertTrue(check.isDisposable(email), email)
        }
    }

    func testBundledListAllowsRealProviders() {
        let check = DisposableEmail.bundled
        for email in ["a@gmail.com", "a@outlook.com", "a@yahoo.com", "a@icloud.com", "a@proton.me",
                      "abc123@privaterelay.appleid.com", "a@ualberta.ca", "a@du.ac.bd"] {
            XCTAssertFalse(check.isDisposable(email), email)
        }
    }

    func testMatchesSubdomainsCaseAndSpaces() {
        let check = DisposableEmail(domains: ["mailinator.com"])
        XCTAssertTrue(check.isDisposable("  Someone@Sub.MAILINATOR.com "))
        XCTAssertTrue(check.isDisposable("a@mailinator.com."))
        XCTAssertFalse(check.isDisposable("a@notmailinator.com"))
        XCTAssertFalse(check.isDisposable("a@mailinator.com.bd"))
    }

    func testNeverMatchesATopLevelDomainOrBadInput() {
        let check = DisposableEmail(domains: ["com", "privaterelay.appleid.com"])
        XCTAssertFalse(check.isDisposable("a@gmail.com"))
        XCTAssertFalse(check.isDisposable("x@privaterelay.appleid.com"))
        XCTAssertFalse(check.isDisposable("no-at-sign"))
        XCTAssertFalse(check.isDisposable("a@"))
    }

    func testParseSkipsCommentsAndBlankLines() {
        XCTAssertEqual(DisposableEmail.parse("# header\n\nfoo.com\n bar.org \n"), ["foo.com", "bar.org"])
    }
}
