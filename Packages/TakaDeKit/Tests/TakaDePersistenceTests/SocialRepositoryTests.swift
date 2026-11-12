import XCTest
import TakaDeCore
@testable import TakaDePersistence

final class SocialRepositoryTests: XCTestCase {
    private let key = String(repeating: "A", count: 43)

    private func makeFriend(_ repo: SQLiteLedgerRepository, account: String = "acct-1", code: String = "7F3K9QXM",
                            name: String = "রাফি") async throws -> Friend {
        let friend = Friend(accountID: account, code: FriendCode(raw: code)!, publicKey: key, name: name)
        try await repo.save(friend)
        return friend
    }

    func testFriendsAreScopedToTheAccount() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        _ = try await makeFriend(repo, account: "acct-2", code: "00000000", name: "Mitu")
        let mine = try await repo.friends(account: "acct-1")
        XCTAssertEqual(mine.map(\.id), [rafi.id])
        // Names are kept exactly as typed.
        XCTAssertEqual(mine.first?.name, "রাফি")
        let byCode = try await repo.friend(account: "acct-1", code: rafi.code)
        XCTAssertEqual(byCode?.id, rafi.id)
        let otherAccount = try await repo.friend(account: "acct-2", code: rafi.code)
        XCTAssertNil(otherAccount)
    }

    func testMessagesUpdatePreviewAndUnread() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        let first = Date(timeIntervalSince1970: 1_000)
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .outgoing, text: "Hotel money?", at: first, state: .sent))
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .incoming, text: "Sending tonight",
                                          at: first.addingTimeInterval(60), state: .received))
        var stored = try await repo.friend(id: rafi.id)
        XCTAssertEqual(stored?.unread, 1)
        XCTAssertEqual(stored?.lastMessagePreview, "Sending tonight")

        // An older message arriving late doesn't replace the newer preview.
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .incoming, text: "Late one",
                                          at: first.addingTimeInterval(-60), state: .received))
        stored = try await repo.friend(id: rafi.id)
        XCTAssertEqual(stored?.lastMessagePreview, "Sending tonight")
        XCTAssertEqual(stored?.unread, 2)

        let messages = try await repo.messages(with: rafi.id)
        XCTAssertEqual(messages.map(\.text), ["Late one", "Hotel money?", "Sending tonight"])

        try await repo.markRead(rafi.id)
        stored = try await repo.friend(id: rafi.id)
        XCTAssertEqual(stored?.unread, 0)
    }

    func testTheSameMessageIsSavedOnce() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        let message = FriendMessage(friendID: rafi.id, direction: .incoming, text: "Hi", state: .received)
        let firstTime = try await repo.save(message)
        let secondTime = try await repo.save(message)
        XCTAssertTrue(firstTime)
        XCTAssertFalse(secondTime)
        let messages = try await repo.messages(with: rafi.id)
        XCTAssertEqual(messages.count, 1)
        let stored = try await repo.friend(id: rafi.id)
        XCTAssertEqual(stored?.unread, 1)
    }

    func testSendingStateUpdates() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        var message = FriendMessage(friendID: rafi.id, direction: .outgoing, text: "Hi", state: .sending)
        try await repo.save(message)
        message.state = .failed
        try await repo.save(message)
        let messages = try await repo.messages(with: rafi.id)
        XCTAssertEqual(messages.map(\.state), [.failed])
    }

    func testDeletingAFriendRemovesTheirMessages() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .incoming, text: "Hi", state: .received))
        try await repo.deleteFriend(rafi.id)
        let messages = try await repo.messages(with: rafi.id)
        XCTAssertTrue(messages.isEmpty)
        let friends = try await repo.friends(account: "acct-1")
        XCTAssertTrue(friends.isEmpty)
    }

    func testExportAndEraseIncludeFriends() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .incoming, text: "Hi", state: .received))
        let export = try await repo.export()
        XCTAssertEqual(export.friends?.first?.messages.map(\.text), ["Hi"])
        try await repo.eraseEverything()
        let friends = try await repo.friends(account: "acct-1")
        XCTAssertTrue(friends.isEmpty)
    }

    func testCleanedMessageText() {
        XCTAssertEqual(FriendMessage.cleaned("  hi \n"), "hi")
        XCTAssertNil(FriendMessage.cleaned("   "))
        XCTAssertNil(FriendMessage.cleaned(String(repeating: "a", count: FriendMessage.maxLength + 1)))
        XCTAssertNotNil(FriendMessage.cleaned(String(repeating: "ক", count: FriendMessage.maxLength)))
    }

    func testPaymentAskIsStoredWithTheMessage() async throws {
        let repo = try SQLiteLedgerRepository()
        let rafi = try await makeFriend(repo)
        let ask = PaymentAsk(kind: .pay, groupID: GroupID(), groupName: "Trip", from: MemberID(), to: MemberID(),
                             amount: Money(minorUnits: 50_000), handles: [.init(rail: .bkash, handle: "01712345678")])
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .incoming, text: "Please pay me ৳500", state: .received, ask: ask))
        try await repo.save(FriendMessage(friendID: rafi.id, direction: .incoming, text: "Thanks", state: .received))
        let stored = try await repo.messages(with: rafi.id)
        XCTAssertEqual(stored.first?.ask, ask)
        XCTAssertNil(stored.last?.ask)
        let friend = try await repo.friend(id: rafi.id)
        XCTAssertEqual(friend?.lastMessagePreview, "Thanks")
    }

    func testEnvelopeRoundTrips() throws {
        let envelope = FriendEnvelope(kind: .text, fromName: "সাবিত", text: "৳500 for dinner")
        let data = try JSONEncoder().encode(envelope)
        XCTAssertEqual(try JSONDecoder().decode(FriendEnvelope.self, from: data), envelope)
    }
}

final class FriendProfileTests: XCTestCase {
    func testQRCarriesTheNameExactly() throws {
        let code = try XCTUnwrap(FriendCode(raw: "7F3K9QXM"))
        let url = code.url(name: "সাবিত কামালী")
        XCTAssertEqual(FriendCode(scanned: url.absoluteString), code)
        XCTAssertEqual(FriendCode.sharedName(inScanned: url.absoluteString), "সাবিত কামালী")
        // No name, or not a name: the plain QR.
        XCTAssertEqual(code.url(name: nil), code.url)
        XCTAssertEqual(code.url(name: "🙂"), code.url)
        XCTAssertNil(FriendCode.sharedName(inScanned: code.url.absoluteString))
        XCTAssertNil(FriendCode.sharedName(inScanned: "takade://join?n=Rafi"))
    }

    func testDisplayNameFallsBackToTheID() throws {
        let code = try XCTUnwrap(FriendCode(raw: "7F3K9QXM"))
        var friend = Friend(accountID: "a", code: code, publicKey: "k", name: "", namedByMe: false)
        XCTAssertEqual(friend.displayName, "TKD-7F3K-9QXM")
        friend.name = "Rafi"
        XCTAssertEqual(friend.displayName, "Rafi")
    }

    func testNamedByMeIsStored() async throws {
        let repo = try SQLiteLedgerRepository()
        let friend = Friend(accountID: "a", code: FriendCode(raw: "7F3K9QXM")!, publicKey: "k", name: "", namedByMe: false)
        try await repo.save(friend)
        var stored = try await repo.friend(id: friend.id)
        XCTAssertEqual(stored?.namedByMe, false)
        stored?.name = "Rafi"
        stored?.namedByMe = true
        try await repo.save(stored!)
        let again = try await repo.friend(id: friend.id)
        XCTAssertEqual(again?.namedByMe, true)
        XCTAssertEqual(again?.name, "Rafi")
    }
}
