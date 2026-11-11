import XCTest
@testable import TakaDeCore

final class SettlementTests: XCTestCase {
    let a = MemberID(), b = MemberID()

    func make() throws -> Settlement {
        try Settlement(groupID: GroupID(), from: a, to: b, amount: Money(minorUnits: 45_000), method: .bkash)
    }

    func testCannotConfirmWithoutProviderEvidence() throws {
        var s = try make()
        try s.transition(to: .reportedUnverified)
        XCTAssertThrowsError(try s.transition(to: .confirmed))
        XCTAssertEqual(s.status, .reportedUnverified)
        try s.transition(to: .confirmed, withProviderEvidence: true)
        XCTAssertEqual(s.status, .confirmed)
    }

    func testCannotSkipStraightToConfirmed() throws {
        var s = try make()
        XCTAssertThrowsError(try s.transition(to: .confirmed, withProviderEvidence: true))
    }

    func testRejectsSelfAndNonPositive() {
        XCTAssertThrowsError(try Settlement(groupID: GroupID(), from: a, to: a, amount: Money(minorUnits: 1), method: .cash))
        XCTAssertThrowsError(try Settlement(groupID: GroupID(), from: a, to: b, amount: .zero(), method: .cash))
    }

    func testOnlyRecipientCanAcknowledge() throws {
        var s = try make()
        XCTAssertThrowsError(try s.acknowledge(by: a))
        XCTAssertThrowsError(try s.transition(to: .acknowledgedByRecipient))
        try s.acknowledge(by: b)
        XCTAssertEqual(s.status, .acknowledgedByRecipient)
        XCTAssertTrue(s.status.countsTowardBalance)
    }

    func testDuplicateReferenceIgnoresCaseSpacesAndDashes() throws {
        let group = GroupID(), a = MemberID(), b = MemberID()
        var first = try Settlement(groupID: group, from: a, to: b, amount: Money(minorUnits: 500_00), method: .bkash, userReference: "8N7A6B5C4D")
        try first.transition(to: .reportedUnverified)
        XCTAssertEqual(Settlement.duplicate(ofReference: "8n7a 6b5c-4d", in: [first])?.id, first.id)
        XCTAssertNil(Settlement.duplicate(ofReference: "9ZZZ", in: [first]))
        XCTAssertNil(Settlement.duplicate(ofReference: "  ", in: [first]))
        XCTAssertNil(Settlement.duplicate(ofReference: nil, in: [first]))
    }

    func testReversedSettlementDoesNotBlockItsReference() throws {
        let group = GroupID(), a = MemberID(), b = MemberID()
        var reversed = try Settlement(groupID: group, from: a, to: b, amount: Money(minorUnits: 500_00), method: .bkash, userReference: "ABC123")
        try reversed.transition(to: .reportedUnverified)
        try reversed.transition(to: .reversed)
        XCTAssertNil(Settlement.duplicate(ofReference: "ABC123", in: [reversed]))
    }
}
