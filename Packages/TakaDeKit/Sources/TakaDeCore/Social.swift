import Foundation

/// Someone in the Social tab (docs/adr/0025-friend-messages.md): a person with a TakaDe
/// account, known on this phone by their TakaDe ID, their public key and the name this
/// phone gave them. Names never go to the server.
public struct Friend: Identifiable, Hashable, Sendable, Codable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        /// Added on this phone, or a request that was accepted.
        case friend
        /// They added you or wrote first, and you haven't accepted yet.
        case request
        /// Blocked: hidden, and the server drops what they send.
        case blocked
    }

    public let id: UUID
    /// The TakaDe account this friend belongs to on this phone, so another account signing
    /// in here doesn't see them.
    public var accountID: String
    public var code: FriendCode
    /// X25519 public key, base64url. Pinned when first seen; a change is noted in the chat.
    public var publicKey: String
    /// The name typed on this phone, or the name they gave themselves. Kept exactly as
    /// entered. Empty until one is known; `displayName` falls back to their TakaDe ID.
    public var name: String
    /// True when the name was typed on this phone, so their own name doesn't replace it.
    public var namedByMe: Bool
    public var status: Status
    public var addedAt: Date
    public var lastMessageAt: Date?
    public var lastMessagePreview: String?
    public var unread: Int

    public init(id: UUID = UUID(), accountID: String, code: FriendCode, publicKey: String, name: String,
                namedByMe: Bool = true, status: Status = .friend, addedAt: Date = Date(), lastMessageAt: Date? = nil,
                lastMessagePreview: String? = nil, unread: Int = 0) {
        self.id = id
        self.accountID = accountID
        self.code = code
        self.publicKey = publicKey
        self.name = name
        self.namedByMe = namedByMe
        self.status = status
        self.addedAt = addedAt
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.unread = unread
    }

    /// Their name, or their TakaDe ID while no name is known yet.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? code.description : name
    }
}

extension FriendCode: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let code = FriendCode(raw: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a TakaDe ID"))
        }
        self = code
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

/// One message in a chat. Text only. Kept on this phone; the server holds a sealed copy
/// only until the friend's phone collects it.
public struct FriendMessage: Identifiable, Hashable, Sendable, Codable {
    public enum Direction: String, Codable, Sendable {
        case outgoing
        case incoming
        /// A note from TakaDe in the chat, like "Their phone changed".
        case notice
    }

    public enum State: String, Codable, Sendable {
        case sending
        /// Left on the server for their phone. Not proof they read it.
        case sent
        case failed
        case received
    }

    /// The same id on both phones, so a message fetched twice is saved once.
    public let id: UUID
    public let friendID: UUID
    public var direction: Direction
    public var text: String
    public var at: Date
    public var state: State
    /// A payment request or proof request this message carries. `text` still holds the
    /// same thing in words, for the chat list preview and for older versions of the app.
    public var ask: PaymentAsk?

    public init(id: UUID = UUID(), friendID: UUID, direction: Direction, text: String, at: Date = Date(), state: State,
                ask: PaymentAsk? = nil) {
        self.id = id
        self.friendID = friendID
        self.direction = direction
        self.text = text
        self.at = at
        self.state = state
        self.ask = ask
    }

    /// Longest message, in characters. The server refuses larger sealed messages.
    public static let maxLength = 1000

    /// The text as it will be sent: trimmed, and nil when empty or too long.
    public static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}

/// What a message carries inside its sealed envelope. The server sees none of it.
public struct FriendEnvelope: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// "I added you": lets the other phone show a request with the sender's name and photo.
        case hello
        /// The sender's own name and photo, sent back once they accept (never to a stranger).
        case profile
        case text
    }

    public var kind: Kind
    public var id: UUID
    /// The sender's own name, so the other phone can show who it is. Never stored on the server.
    public var fromName: String
    public var text: String?
    /// A small square JPEG of the sender's profile photo, base64. Hello and profile only.
    public var photo: String?
    /// A payment or proof request, on a `.text` message whose text says the same in words.
    /// Riding on `.text` means a phone with an older TakaDe still shows the words.
    public var ask: PaymentAsk?

    /// Largest photo accepted, in bytes before base64.
    public static let maxPhotoBytes = 16_000

    public init(kind: Kind, id: UUID = UUID(), fromName: String, text: String? = nil, photo: String? = nil, ask: PaymentAsk? = nil) {
        self.kind = kind
        self.id = id
        self.fromName = fromName
        self.text = text
        self.photo = photo
        self.ask = ask
    }

    private enum CodingKeys: String, CodingKey { case kind, id, fromName, text, photo, ask }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(UUID.self, forKey: .id)
        fromName = try container.decode(String.self, forKey: .fromName)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        photo = try container.decodeIfPresent(String.self, forKey: .photo)
        // An ask this version can't read (a newer kind, say) is dropped; the words still show.
        ask = (try? container.decodeIfPresent(PaymentAsk.self, forKey: .ask))?.validated()
    }
}

/// Storage for friends and messages on this phone.
public protocol SocialRepository: Sendable {
    /// Everyone for this account, newest conversation first.
    func friends(account: String) async throws -> [Friend]
    func friend(id: UUID) async throws -> Friend?
    func friend(account: String, code: FriendCode) async throws -> Friend?
    func friend(account: String, publicKey: String) async throws -> Friend?
    func save(_ friend: Friend) async throws
    /// Removes the friend and their messages from this phone.
    func deleteFriend(_ id: UUID) async throws

    func messages(with friend: UUID) async throws -> [FriendMessage]
    /// Saves a message and updates the friend's preview, time and unread count. Saving a
    /// message id that is already stored only updates its state, so a message fetched
    /// twice shows once. Returns false when it was already there.
    @discardableResult
    func save(_ message: FriendMessage) async throws -> Bool
    func markRead(_ friend: UUID) async throws
}

extension FriendCode {
    /// The QR code with the owner's own name in it, so whoever scans it in person sees the
    /// name straight away (Sabit, 2026-11-12). The name goes camera to camera, never through
    /// the server. Typed or shared IDs carry no name.
    public func url(name: String?) -> URL {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, PersonName.isValid(trimmed),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "n", value: trimmed)]
        return components.url ?? url
    }

    /// The name inside a scanned TakaDe QR code, when it has a valid one.
    public static func sharedName(inScanned text: String) -> String? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == GroupInvite.scheme, components.host?.lowercased() == urlHost,
              let name = components.queryItems?.first(where: { $0.name == "n" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              PersonName.isValid(name) else { return nil }
        return name
    }
}
