import CryptoKit
import Foundation
import Observation
import TakaDeCore

/// The Social tab (docs/adr/0025-friend-messages.md): people added by TakaDe ID, and text
/// messages with them.
///
/// Each message is sealed on this phone with HPKE in authenticated mode: to the friend's
/// public key, and signed-in-the-cryptographic-sense by this account's own key, so their
/// phone can tell it came from the key it knows. The server keeps the sealed message until
/// their phone collects it, then it is deleted there. Messages and names live in SQLite on
/// each phone. Realtime tells an open app at once that something is waiting, and carries
/// "typing" signals on a channel named from a secret only the two phones share.
@MainActor
@Observable
final class SocialModel {
    private(set) var people: [Friend] = []
    /// Bumped when messages change, so an open chat reloads.
    private(set) var revision = 0
    /// Friends who are typing right now.
    private(set) var typing: Set<UUID> = []
    /// The chat on screen, if any: its messages count as read when they arrive.
    var openChat: UUID?

    @ObservationIgnored private let store: SocialRepository
    @ObservationIgnored private let account: AccountModel
    @ObservationIgnored private let friends: Friends
    @ObservationIgnored private var realtime: RealtimeClient?
    @ObservationIgnored private var realtimeUser: String?
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var fetchAgain = false
    @ObservationIgnored private var typingExpiry: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastTypingSent: [UUID: Date] = [:]
    @ObservationIgnored private var typingTopics: [String: UUID] = [:]

    private static let info = Data("takade.friend-message.v1".utf8)
    private static let inboxTopic = "inbox"

    init(store: SocialRepository, account: AccountModel, friends: Friends) {
        self.store = store
        self.account = account
        self.friends = friends
    }

    var isAvailable: Bool { friends.isAvailable }

    var chats: [Friend] { people.filter { $0.status == .friend } }
    var requests: [Friend] { people.filter { $0.status == .request } }
    var blocked: [Friend] { people.filter { $0.status == .blocked } }
    var unreadTotal: Int { people.filter { $0.status != .blocked }.reduce(0) { $0 + $1.unread } }

    // MARK: Lifecycle

    /// At launch and whenever the app comes back: makes sure this account has an ID and key
    /// (so friends can reach it), connects Realtime and collects waiting messages.
    func start() async {
        guard let user = friends.userID else {
            stop()
            people = []
            return
        }
        if realtimeUser != user { stop() }
        await reload()
        if friends.myCode == nil { try? await friends.ensureID() }
        connect(user: user)
        await fetchInbox()
    }

    /// When the app goes to the background. Messages wait on the server until it's back.
    func stop() {
        realtime?.disconnect()
        realtime = nil
        realtimeUser = nil
        typingTopics = [:]
        typing = []
    }

    func reload() async {
        guard let user = friends.userID else {
            people = []
            return
        }
        people = (try? await store.friends(account: user)) ?? []
    }

    private func connect(user: String) {
        guard realtime == nil, let supabase = account.supabase else { return }
        let client = RealtimeClient(config: supabase.config) { try await supabase.accessToken() }
        client.onEvent = { [weak self] event in self?.handle(event) }
        // No column filter: the app may only read a message's id and time, and Realtime sends
        // each phone only the rows its row-level security lets it see (its own messages).
        client.listen(topic: Self.inboxTopic, table: "friend_message")
        client.connect()
        realtime = client
        realtimeUser = user
    }

    private func handle(_ event: RealtimeClient.Event) {
        switch event {
        case .change(let topic) where topic == Self.inboxTopic:
            Task { await fetchInbox() }
        case .broadcast(let topic, let name, _):
            guard let friend = typingTopics[topic] else { return }
            if name == "typing" { showTyping(friend) } else if name == "stopped" { hideTyping(friend) }
        default:
            break
        }
    }

    // MARK: Adding people

    /// Adds someone by TakaDe ID with the name typed on this phone, and lets their phone
    /// know (a sealed "hello" carrying your own name), so you show up in their Social tab.
    @discardableResult
    func add(code: FriendCode, name: String, myName: String,
             key known: Curve25519.KeyAgreement.PublicKey? = nil) async throws -> Friend {
        guard let user = friends.userID else { throw Friends.Failure.notSignedIn }
        let key: Curve25519.KeyAgreement.PublicKey
        if let known { key = known } else { key = try await friends.lookUp(code) }
        let publicKey = key.rawRepresentation.base64URLEncoded
        var friend = try await store.friend(account: user, code: code)
            ?? Friend(accountID: user, code: code, publicKey: publicKey, name: name)
        friend.name = name
        friend.publicKey = publicKey
        friend.status = .friend
        try await store.save(friend)
        await reload()
        _ = try? await deliver(FriendEnvelope(kind: .hello, fromName: myName), to: friend)
        return friend
    }

    /// Someone who wrote first, now in your chats. Their name stays as they gave it.
    func accept(_ friend: Friend) async {
        var friend = friend
        friend.status = .friend
        try? await store.save(friend)
        await reload()
    }

    /// Stops their messages: the server drops what they send, and it isn't told to them.
    func block(_ friend: Friend) async throws {
        guard let supabase = account.supabase else { throw Friends.Failure.notSignedIn }
        _ = try await friends.call {
            try await supabase.rest("rpc/block_friend", method: "POST", body: ["p_code": friend.code.raw])
        }
        var friend = friend
        friend.status = .blocked
        friend.unread = 0
        try await store.save(friend)
        await reload()
    }

    func unblock(_ friend: Friend) async throws {
        guard let supabase = account.supabase else { throw Friends.Failure.notSignedIn }
        _ = try await friends.call {
            try await supabase.rest("rpc/unblock_friend", method: "POST", body: ["p_code": friend.code.raw])
        }
        var friend = friend
        friend.status = .friend
        try await store.save(friend)
        await reload()
    }

    /// Removes them and the chat from this phone. If they write again, it shows as a request.
    func remove(_ friend: Friend) async {
        try? await store.deleteFriend(friend.id)
        await reload()
        revision += 1
    }

    // MARK: Messages

    func messages(with friend: UUID) async -> [FriendMessage] {
        (try? await store.messages(with: friend)) ?? []
    }

    func markRead(_ friend: UUID) async {
        guard people.first(where: { $0.id == friend })?.unread ?? 0 > 0 else { return }
        try? await store.markRead(friend)
        await reload()
    }

    /// Shows the message at once, then seals and sends it. A failed send stays in the chat
    /// with "Not sent. Tap to try again."
    func send(_ text: String, to friend: Friend, myName: String) async {
        guard let text = FriendMessage.cleaned(text) else { return }
        var message = FriendMessage(friendID: friend.id, direction: .outgoing, text: text, state: .sending)
        _ = try? await store.save(message)
        revision += 1
        stoppedTyping(in: friend)
        message.state = await sendState(of: message, to: friend, myName: myName)
        _ = try? await store.save(message)
        await reload()
        revision += 1
    }

    func retry(_ message: FriendMessage, to friend: Friend, myName: String) async {
        var message = message
        message.state = .sending
        _ = try? await store.save(message)
        revision += 1
        message.state = await sendState(of: message, to: friend, myName: myName)
        _ = try? await store.save(message)
        revision += 1
    }

    private func sendState(of message: FriendMessage, to friend: Friend, myName: String) async -> FriendMessage.State {
        let envelope = FriendEnvelope(kind: .text, id: message.id, fromName: myName, text: message.text)
        do {
            return try await deliver(envelope, to: friend) ? .sent : .failed
        } catch {
            return .failed
        }
    }

    /// True when the server took it; false when no account has their ID any more.
    @discardableResult
    private func deliver(_ envelope: FriendEnvelope, to friend: Friend) async throws -> Bool {
        guard let supabase = account.supabase, let user = friends.userID,
              let mine = friends.privateKey(for: user, creating: false),
              let raw = Data(base64URLEncoded: friend.publicKey),
              let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else {
            throw Friends.Failure.notSignedIn
        }
        let sealed = try Self.seal(JSONEncoder().encode(envelope), to: theirs, from: mine)
        let data = try await friends.call {
            try await supabase.rest("rpc/send_friend_message", method: "POST", body: ["p_code": friend.code.raw, "p_sealed": sealed])
        }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    /// Collects waiting messages, checks each against the sender's key, saves it, and
    /// deletes it from the server. Runs at launch, when the app comes back, when the Social
    /// tab opens, and the moment Realtime says something arrived.
    func fetchInbox() async {
        guard !fetching else {
            fetchAgain = true
            return
        }
        fetching = true
        defer { fetching = false }
        repeat {
            fetchAgain = false
            await fetchOnce()
        } while fetchAgain
    }

    private func fetchOnce() async {
        guard let supabase = account.supabase, let user = friends.userID,
              let mine = friends.privateKey(for: user, creating: false) else { return }
        struct Row: Decodable {
            let id: UUID
            let sealed: String
            let created_at: Date
            let from_code: String?
            let from_key: String?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return Self.parseDate(text) ?? Date()
        }
        guard let data = try? await supabase.rest("rpc/friend_inbox", method: "POST", body: [String: Any]()),
              let rows = try? decoder.decode([Row].self, from: data), !rows.isEmpty else { return }
        var done: [UUID] = []
        var changed = false
        for row in rows {
            defer { done.append(row.id) }
            guard let codeText = row.from_code, let code = FriendCode(raw: codeText), let keyText = row.from_key,
                  let raw = Data(base64URLEncoded: keyText),
                  let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw),
                  let plain = try? Self.open(row.sealed, with: mine, from: theirs),
                  let envelope = try? JSONDecoder().decode(FriendEnvelope.self, from: plain) else {
                // Sealed to a key this phone doesn't have, from a key that changed, or damaged.
                continue
            }
            if await receive(envelope, from: code, key: keyText, at: row.created_at, account: user) { changed = true }
        }
        // Collected (or unreadable): no longer needed on the server. Ids are UUIDs from the server.
        let list = done.map(\.uuidString).joined(separator: ",")
        _ = try? await supabase.rest("friend_message?id=in.(\(list))", method: "DELETE", prefer: "return=minimal")
        if changed {
            await reload()
            revision += 1
            if let open = openChat { await markRead(open) }
        }
    }

    private func receive(_ envelope: FriendEnvelope, from code: FriendCode, key: String, at: Date, account user: String) async -> Bool {
        let byKey = try? await store.friend(account: user, publicKey: key)
        let byCode = try? await store.friend(account: user, code: code)
        var friend: Friend
        if let known = byKey ?? byCode {
            friend = known
            if friend.status == .blocked { return false }
            var notice: String?
            if friend.publicKey != key {
                notice = String(localized: "\(friend.name) is using TakaDe on a new phone.", bundle: .appLanguage)
            }
            if friend.publicKey != key || friend.code != code {
                friend.publicKey = key
                friend.code = code
                try? await store.save(friend)
            }
            if let notice {
                _ = try? await store.save(FriendMessage(friendID: friend.id, direction: .notice, text: notice, at: at, state: .received))
            }
        } else {
            let name = Self.cleanName(envelope.fromName) ?? code.description
            friend = Friend(accountID: user, code: code, publicKey: key, name: name, status: .request, addedAt: at)
            try? await store.save(friend)
        }
        hideTyping(friend.id)
        guard envelope.kind == .text, let text = envelope.text.flatMap(FriendMessage.cleaned) else { return true }
        _ = try? await store.save(FriendMessage(id: envelope.id, friendID: friend.id, direction: .incoming, text: text, at: at, state: .received))
        return true
    }

    /// The sender's own name, exactly as they gave it, when it passes the app's name rule;
    /// otherwise the request shows their TakaDe ID.
    private static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonName.isValid(trimmed) ? trimmed : nil
    }

    // MARK: Typing

    /// Called when a chat opens: listens on the typing channel the two phones share.
    func openTyping(with friend: Friend) {
        guard let topic = typingTopic(with: friend) else { return }
        typingTopics[topic] = friend.id
        realtime?.joinBroadcast(topic: topic)
    }

    func closeTyping(with friend: Friend) {
        stoppedTyping(in: friend)
        guard let topic = typingTopic(with: friend) else { return }
        typingTopics[topic] = nil
        realtime?.leave(topic: topic)
        hideTyping(friend.id)
    }

    /// While the person types: at most one signal every 2.5 seconds.
    func userTyped(in friend: Friend) {
        let now = Date()
        if let last = lastTypingSent[friend.id], now.timeIntervalSince(last) < 2.5 { return }
        lastTypingSent[friend.id] = now
        guard let topic = typingTopic(with: friend) else { return }
        realtime?.broadcast(topic: topic, event: "typing")
    }

    func stoppedTyping(in friend: Friend) {
        guard lastTypingSent.removeValue(forKey: friend.id) != nil, let topic = typingTopic(with: friend) else { return }
        realtime?.broadcast(topic: topic, event: "stopped")
    }

    private func showTyping(_ friend: UUID) {
        typing.insert(friend)
        typingExpiry[friend]?.cancel()
        // No signal for 6 seconds: they stopped, or their app closed.
        typingExpiry[friend] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.hideTyping(friend)
        }
    }

    private func hideTyping(_ friend: UUID) {
        typingExpiry.removeValue(forKey: friend)?.cancel()
        typing.remove(friend)
    }

    /// The same on both phones and unknowable to anyone else: derived from the X25519
    /// secret between the two keys. The server sees the channel name and when signals pass,
    /// not who is in it.
    private func typingTopic(with friend: Friend) -> String? {
        guard let user = friends.userID, let mine = friends.privateKey(for: user, creating: false),
              let raw = Data(base64URLEncoded: friend.publicKey),
              let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw),
              let secret = try? mine.sharedSecretFromKeyAgreement(with: theirs) else { return nil }
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data("takade.typing.v1".utf8),
                                                 outputByteCount: 16)
        let hex = key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        return "typing-" + hex
    }

    // MARK: Sealing

    /// "m1." + encapsulated key + "." + ciphertext, both base64url. HPKE auth mode: only the
    /// holder of `to`'s private key can open it, and opening checks it was sealed by `from`.
    static func seal(_ plain: Data, to recipient: Curve25519.KeyAgreement.PublicKey,
                     from sender: Curve25519.KeyAgreement.PrivateKey) throws -> String {
        var hpke = try HPKE.Sender(recipientKey: recipient, ciphersuite: Friends.suite, info: info, authenticatedBy: sender)
        let ciphertext = try hpke.seal(plain)
        return "m1." + hpke.encapsulatedKey.base64URLEncoded + "." + ciphertext.base64URLEncoded
    }

    static func open(_ sealed: String, with key: Curve25519.KeyAgreement.PrivateKey,
                     from sender: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let parts = sealed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "m1", let encapsulated = Data(base64URLEncoded: String(parts[1])),
              let ciphertext = Data(base64URLEncoded: String(parts[2])) else { throw Friends.Failure.server }
        var hpke = try HPKE.Recipient(privateKey: key, ciphersuite: Friends.suite, info: info,
                                      encapsulatedKey: encapsulated, authenticatedBy: sender)
        return try hpke.open(ciphertext)
    }

    /// Postgres sends microseconds ("…:05.123456+00:00"); the formatter wants milliseconds.
    private nonisolated static func parseDate(_ text: String) -> Date? {
        let text = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
