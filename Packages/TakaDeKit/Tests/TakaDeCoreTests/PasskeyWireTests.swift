import XCTest
@testable import TakaDeCore

final class PasskeyWireTests: XCTestCase {
    private let challenge = Data([1, 2, 3, 250, 251, 252])
    private let userID = Data([9, 8, 7, 6])

    func testReadsRegistrationOptions() throws {
        let json: [String: Any] = [
            "challenge_id": "c-1",
            "expires_at": 1_800_000_000,
            "options": [
                "challenge": challenge.base64URLEncoded,
                "rp": ["id": "takadeapp.com", "name": "TakaDe"],
                "user": ["id": userID.base64URLEncoded, "name": "a@example.com", "displayName": "a@example.com"],
                "pubKeyCredParams": [["type": "public-key", "alg": -7]],
                "excludeCredentials": [["type": "public-key", "id": Data([5, 5]).base64URLEncoded]],
            ],
        ]
        let options = try PasskeyWire.creationOptions(from: json)
        XCTAssertEqual(options.challengeID, "c-1")
        XCTAssertEqual(options.challenge, challenge)
        XCTAssertEqual(options.relyingPartyID, "takadeapp.com")
        XCTAssertEqual(options.userID, userID)
        XCTAssertEqual(options.userName, "a@example.com")
        XCTAssertEqual(options.excludedCredentialIDs, [Data([5, 5])])
    }

    func testAcceptsOptionsWrappedInPublicKey() throws {
        let json: [String: Any] = [
            "challenge_id": "c-2",
            "options": ["publicKey": ["challenge": challenge.base64URLEncoded, "rpId": "takadeapp.com"]],
        ]
        let options = try PasskeyWire.requestOptions(from: json)
        XCTAssertEqual(options.challenge, challenge)
        XCTAssertEqual(options.relyingPartyID, "takadeapp.com")
        XCTAssertEqual(options.allowedCredentialIDs, [])
    }

    func testRejectsMissingOrBrokenFields() {
        XCTAssertThrowsError(try PasskeyWire.requestOptions(from: ["options": ["challenge": "AQID"]]))
        XCTAssertThrowsError(try PasskeyWire.requestOptions(from: ["challenge_id": "x", "options": ["challenge": "not base64!"]]))
        XCTAssertThrowsError(try PasskeyWire.creationOptions(from: [
            "challenge_id": "x",
            "options": ["challenge": "AQID", "user": ["id": "AQID"]],
        ]), "no relying party")
    }

    func testRegistrationCredentialIsBase64URLWithoutPadding() throws {
        let id = Data([0xFB, 0xFF, 0x01])
        let credential = PasskeyWire.registrationCredential(
            credentialID: id, clientDataJSON: Data("{}".utf8), attestationObject: Data([0xFF]), attachment: "platform")
        XCTAssertEqual(credential["id"] as? String, "-_8B")
        XCTAssertEqual(credential["rawId"] as? String, "-_8B")
        XCTAssertEqual(credential["type"] as? String, "public-key")
        XCTAssertEqual(credential["authenticatorAttachment"] as? String, "platform")
        let response = try XCTUnwrap(credential["response"] as? [String: Any])
        XCTAssertEqual(response["clientDataJSON"] as? String, "e30")
        XCTAssertEqual(response["attestationObject"] as? String, "_w")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(credential))
    }

    func testAssertionCredentialLeavesOutAnEmptyUserHandle() throws {
        let credential = PasskeyWire.assertionCredential(
            credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
            signature: Data([4]), userHandle: Data(), attachment: nil)
        let response = try XCTUnwrap(credential["response"] as? [String: Any])
        XCTAssertNil(response["userHandle"])
        XCTAssertNil(credential["authenticatorAttachment"])
        XCTAssertEqual(response["signature"] as? String, "BA")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(credential))
    }

    func testReadsTheList() {
        let items = PasskeyWire.items(from: [
            ["id": "p1", "friendly_name": "iCloud Keychain", "created_at": "2026-11-14T05:00:09.123456Z"],
            ["id": "p2", "friendly_name": "  ", "created_at": "2026-11-14T05:00:09Z", "last_used_at": "2026-11-15T01:00:00Z"],
            ["friendly_name": "no id"],
        ] as [[String: Any]])
        XCTAssertEqual(items.map(\.id), ["p1", "p2"])
        XCTAssertEqual(items[0].friendlyName, "iCloud Keychain")
        XCTAssertNil(items[1].friendlyName)
        XCTAssertNotNil(items[0].createdAt)
        XCTAssertNotNil(items[1].lastUsedAt)
    }
}
