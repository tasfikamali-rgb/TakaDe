import XCTest
@testable import TakaDeCore

final class PaymentAskTests: XCTestCase {
    private let group = GroupID()
    private let rafi = MemberID()
    private let me = MemberID()
    private let sent = Date(timeIntervalSince1970: 10_000)

    private func pay(_ amount: Int64 = 50_000, handles: [PaymentAsk.Handle] = []) -> PaymentAsk {
        PaymentAsk(kind: .pay, groupID: group, groupName: "Cox's Bazar", from: rafi, to: me,
                   amount: Money(minorUnits: amount), handles: handles)
    }

    private func settlement(_ status: SettlementStatus, at date: Date, reference: String? = nil) throws -> Settlement {
        var s = try Settlement(groupID: group, from: rafi, to: me, amount: Money(minorUnits: 50_000), method: .bkash,
                               userReference: reference, createdAt: date)
        switch status {
        case .acknowledgedByRecipient: try s.acknowledge(by: me)
        case .reversed:
            try s.transition(to: .reportedUnverified)
            try s.transition(to: .reversed)
        case .notStarted: break
        default: try s.transition(to: status)
        }
        return s
    }

    func testValidationRejectsNonsense() {
        XCTAssertNotNil(pay().validated())
        XCTAssertNil(pay(0).validated())
        XCTAssertNil(pay(-5).validated())
        XCTAssertNil(PaymentAsk(kind: .pay, groupID: group, groupName: "x", from: me, to: me, amount: Money(minorUnits: 100)).validated())
        // A proof ask must name its payment.
        XCTAssertNil(PaymentAsk(kind: .proof, groupID: group, groupName: "x", from: rafi, to: me, amount: Money(minorUnits: 100)).validated())
    }

    func testHandlesAreCheckedAndNormalized() throws {
        let ask = pay(handles: [
            .init(rail: .bkash, handle: "+880 1712-345678"),
            .init(rail: .nagad, handle: "12345"),
        ])
        let checked = try XCTUnwrap(ask.validated())
        XCTAssertEqual(checked.handles, [.init(rail: .bkash, handle: "01712345678")])
    }

    func testEnvelopeCarriesTheAsk() throws {
        let ask = pay(handles: [.init(rail: .bkash, handle: "01712345678")])
        let envelope = FriendEnvelope(kind: .text, fromName: "সাবিত", text: "Please pay me ৳500", ask: ask)
        let decoded = try JSONDecoder().decode(FriendEnvelope.self, from: JSONEncoder().encode(envelope))
        XCTAssertEqual(decoded, envelope)
    }

    func testUnknownAskStillShowsTheWords() throws {
        let json = """
        {"kind":"text","id":"\(UUID().uuidString)","fromName":"Rafi","text":"Hello",
         "ask":{"kind":"split-the-moon","amount":1}}
        """
        let decoded = try JSONDecoder().decode(FriendEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.text, "Hello")
        XCTAssertNil(decoded.ask)
    }

    func testPayProgressFollowsTheGroupsPayments() throws {
        let ask = pay()
        XCTAssertEqual(ask.progress(sentAt: sent, in: []), .waiting)
        // A payment recorded well before the request doesn't answer it.
        XCTAssertEqual(ask.progress(sentAt: sent, in: [try settlement(.reportedUnverified, at: sent.addingTimeInterval(-3600))]), .waiting)
        XCTAssertEqual(ask.progress(sentAt: sent, in: [try settlement(.reportedUnverified, at: sent.addingTimeInterval(120))]), .reportedPaid)
        XCTAssertEqual(ask.progress(sentAt: sent, in: [try settlement(.acknowledgedByRecipient, at: sent.addingTimeInterval(120))]), .received)
        // A withdrawn report doesn't count.
        XCTAssertEqual(ask.progress(sentAt: sent, in: [try settlement(.reversed, at: sent.addingTimeInterval(120))]), .waiting)
    }

    func testProofProgressFollowsItsPayment() throws {
        var payment = try settlement(.reportedUnverified, at: sent)
        let ask = PaymentAsk(kind: .proof, groupID: group, groupName: "x", from: rafi, to: me, amount: payment.amount,
                             settlementID: payment.id)
        XCTAssertEqual(ask.progress(sentAt: sent, in: [payment]), .waiting)
        try payment.edit(amount: payment.amount, method: .bkash, userReference: "8N7A6B5C4D", by: rafi)
        XCTAssertEqual(ask.progress(sentAt: sent, in: [payment]), .reference("8N7A6B5C4D"))
        try payment.acknowledge(by: me)
        XCTAssertEqual(ask.progress(sentAt: sent, in: [payment]), .received)
    }
}
