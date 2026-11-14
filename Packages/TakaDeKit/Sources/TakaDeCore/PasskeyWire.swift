import Foundation

/// The JSON that Supabase Auth's passkey endpoints send and expect (docs/adr/0035-passkeys.md),
/// kept apart from AuthenticationServices so it can be tested without a phone.
///
/// The service speaks the W3C WebAuthn JSON format: binary values are base64url without
/// padding. Endpoints, all under `/auth/v1`:
/// - `POST passkeys/registration/options` (signed in) → `{challenge_id, options, expires_at}`
/// - `POST passkeys/registration/verify` (signed in) `{challenge_id, credential}`
/// - `POST passkeys/authentication/options` → `{challenge_id, options, expires_at}`
/// - `POST passkeys/authentication/verify` `{challenge_id, credential}` → a session
/// - `GET passkeys`, `PATCH passkeys/{id}`, `DELETE passkeys/{id}` (signed in)
public enum PasskeyWire {
    public enum Failure: Error, Equatable {
        case malformed(String)
    }

    /// What `registration/options` returned, ready for iOS's passkey sheet.
    public struct CreationOptions: Equatable, Sendable {
        public let challengeID: String
        public let challenge: Data
        public let relyingPartyID: String
        public let userID: Data
        /// The account's name on the service (its email). Shown in iOS's passkey sheet and
        /// in Passwords, so the person can tell which account the passkey is for.
        public let userName: String
        /// Passkeys this account already has, so iOS won't make a second one for it.
        public let excludedCredentialIDs: [Data]
    }

    /// What `authentication/options` returned.
    public struct RequestOptions: Equatable, Sendable {
        public let challengeID: String
        public let challenge: Data
        /// Empty when the service lets the person pick any passkey for the site (the usual case).
        public let relyingPartyID: String?
        public let allowedCredentialIDs: [Data]
    }

    /// One passkey on the account, as `GET passkeys` lists it.
    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let friendlyName: String?
        public let createdAt: Date?
        public let lastUsedAt: Date?

        public init(id: String, friendlyName: String?, createdAt: Date?, lastUsedAt: Date?) {
            self.id = id
            self.friendlyName = friendlyName
            self.createdAt = createdAt
            self.lastUsedAt = lastUsedAt
        }
    }

    // MARK: Reading

    public static func creationOptions(from json: [String: Any]) throws -> CreationOptions {
        let challengeID = try string(json["challenge_id"], "challenge_id")
        let options = try publicKey(json)
        let rp = options["rp"] as? [String: Any] ?? [:]
        let user = options["user"] as? [String: Any] ?? [:]
        let name = (user["name"] as? String) ?? (user["displayName"] as? String) ?? ""
        return CreationOptions(
            challengeID: challengeID,
            challenge: try bytes(options["challenge"], "challenge"),
            relyingPartyID: try string(rp["id"], "rp.id"),
            userID: try bytes(user["id"], "user.id"),
            userName: name,
            excludedCredentialIDs: try credentialIDs(options["excludeCredentials"]))
    }

    public static func requestOptions(from json: [String: Any]) throws -> RequestOptions {
        let challengeID = try string(json["challenge_id"], "challenge_id")
        let options = try publicKey(json)
        let rpID = (options["rpId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return RequestOptions(
            challengeID: challengeID,
            challenge: try bytes(options["challenge"], "challenge"),
            relyingPartyID: rpID,
            allowedCredentialIDs: try credentialIDs(options["allowCredentials"]))
    }

    public static func items(from json: Any) -> [Item] {
        let list = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["passkeys"] as? [[String: Any]]) ?? []
        return list.compactMap { entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let name = (entry["friendly_name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            return Item(id: id, friendlyName: name, createdAt: date(entry["created_at"]), lastUsedAt: date(entry["last_used_at"]))
        }
    }

    // MARK: Writing

    /// The `credential` for `registration/verify`, from what iOS made.
    public static func registrationCredential(credentialID: Data, clientDataJSON: Data, attestationObject: Data,
                                              attachment: String?) -> [String: Any] {
        var credential: [String: Any] = [
            "id": credentialID.base64URLEncoded,
            "rawId": credentialID.base64URLEncoded,
            "type": "public-key",
            "response": [
                "clientDataJSON": clientDataJSON.base64URLEncoded,
                "attestationObject": attestationObject.base64URLEncoded,
                "transports": ["internal", "hybrid"],
            ],
            "clientExtensionResults": [String: Any](),
        ]
        if let attachment { credential["authenticatorAttachment"] = attachment }
        return credential
    }

    /// The `credential` for `authentication/verify`, from what iOS signed.
    public static func assertionCredential(credentialID: Data, clientDataJSON: Data, authenticatorData: Data,
                                           signature: Data, userHandle: Data?, attachment: String?) -> [String: Any] {
        var response: [String: Any] = [
            "clientDataJSON": clientDataJSON.base64URLEncoded,
            "authenticatorData": authenticatorData.base64URLEncoded,
            "signature": signature.base64URLEncoded,
        ]
        if let userHandle, !userHandle.isEmpty { response["userHandle"] = userHandle.base64URLEncoded }
        var credential: [String: Any] = [
            "id": credentialID.base64URLEncoded,
            "rawId": credentialID.base64URLEncoded,
            "type": "public-key",
            "response": response,
            "clientExtensionResults": [String: Any](),
        ]
        if let attachment { credential["authenticatorAttachment"] = attachment }
        return credential
    }

    // MARK: Private

    /// The options object. Some servers wrap it as `{"publicKey": {...}}`; accept both.
    private static func publicKey(_ json: [String: Any]) throws -> [String: Any] {
        guard let options = json["options"] as? [String: Any] else { throw Failure.malformed("options") }
        return (options["publicKey"] as? [String: Any]) ?? options
    }

    private static func string(_ value: Any?, _ field: String) throws -> String {
        guard let text = value as? String, !text.isEmpty else { throw Failure.malformed(field) }
        return text
    }

    private static func bytes(_ value: Any?, _ field: String) throws -> Data {
        guard let text = value as? String, let data = Data(base64URLEncoded: text), !data.isEmpty else {
            throw Failure.malformed(field)
        }
        return data
    }

    private static func credentialIDs(_ value: Any?) throws -> [Data] {
        guard let list = value as? [[String: Any]] else { return [] }
        return try list.map { try bytes($0["id"], "credential id") }
    }

    /// Times like 2026-11-14T05:00:09.123456Z; the fraction is dropped.
    static func date(_ value: Any?) -> Date? {
        guard var text = value as? String else { return nil }
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            text.removeSubrange(dot..<end)
        }
        return ISO8601DateFormatter().date(from: text)
    }
}
