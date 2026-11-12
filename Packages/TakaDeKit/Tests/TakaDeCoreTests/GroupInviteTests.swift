import XCTest
@testable import TakaDeCore

final class GroupInviteTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0 * 7 % 256) })
    private let token = "abcDEF0123456789_-xyzABCD"

    func testLinkRoundTrips() throws {
        let invite = try XCTUnwrap(GroupInvite(groupID: GroupID(), token: token, key: key))
        let url = invite.url
        XCTAssertEqual(url.scheme, "takade")
        XCTAssertTrue(url.absoluteString.contains("#k="))
        XCTAssertEqual(GroupInvite(url: url), invite)
    }

    func testWebsiteLinkIsRead() throws {
        let invite = try XCTUnwrap(GroupInvite(groupID: GroupID(), token: token, key: key))
        let web = try XCTUnwrap(URL(string: "https://takadeapp.com/join?g=\(invite.groupID)&t=\(token)#k=\(key.base64URLEncoded)"))
        XCTAssertEqual(GroupInvite(url: web), invite)
        let other = try XCTUnwrap(URL(string: "https://example.com/join?g=\(invite.groupID)&t=\(token)#k=\(key.base64URLEncoded)"))
        XCTAssertNil(GroupInvite(url: other))
    }

    func testFoundInsidePastedMessage() throws {
        let invite = try XCTUnwrap(GroupInvite(groupID: GroupID(), token: token, key: key))
        let message = "Join \"Sylhet trip\" on TakaDe: \(invite.url.absoluteString). See you!"
        XCTAssertEqual(GroupInvite(text: message), invite)
        XCTAssertNil(GroupInvite(text: "no link here"))
    }

    func testRejectsMissingKeyShortTokenOrWrongKeySize() {
        let group = GroupID()
        XCTAssertNil(GroupInvite(url: URL(string: "takade://join?g=\(group)&t=\(token)")!))
        XCTAssertNil(GroupInvite(url: URL(string: "takade://join?g=\(group)&t=short#k=\(key.base64URLEncoded)")!))
        XCTAssertNil(GroupInvite(url: URL(string: "takade://join?g=\(group)&t=\(token)#k=\(Data(count: 16).base64URLEncoded)")!))
        XCTAssertNil(GroupInvite(url: URL(string: "takade://auth-callback?code=1")!))
    }

    func testBase64URLRoundTrips() {
        for length in [0, 1, 2, 3, 31, 32, 33] {
            let data = Data((0..<length).map { UInt8(($0 * 37 + 250) % 256) })
            XCTAssertEqual(Data(base64URLEncoded: data.base64URLEncoded), data)
        }
        XCTAssertNil(Data(base64URLEncoded: "abc+/"))
    }
}

final class ExpenseReceiptTests: XCTestCase {
    func testReceiptIDRoundTripsAndOldExpensesHaveNone() throws {
        let a = MemberID(), b = MemberID()
        let receipt = UUID()
        let expense = try Expense(groupID: GroupID(), title: "Bazar", total: Money(minorUnits: 50_000),
                                  paidBy: [a: Money(minorUnits: 50_000)], splitRule: .equal([a, b]), receiptID: receipt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(expense)
        XCTAssertEqual(try decoder.decode(Expense.self, from: data).receiptID, receipt)

        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "receiptID")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        XCTAssertNil(try decoder.decode(Expense.self, from: oldData).receiptID)
    }
}
