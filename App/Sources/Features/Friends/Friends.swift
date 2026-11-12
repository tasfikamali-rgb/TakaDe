import CryptoKit
import Foundation
import Observation
import TakaDeCore

/// What a friend invite carries, sealed so only the friend's phone can read it.
struct FriendInvitePayload: Codable, Sendable {
    /// The group's invite link, with its key after the "#".
    var link: String
    var groupName: String
    var fromName: String
    /// The person the sender added for them, so their phone knows who they are in the group.
    var memberID: UUID?
}

/// TakaDe IDs (docs/adr/0021-takade-ids.md). Each account gets a random ID and a key pair.
/// The server keeps the ID and the public key only. Someone who knows the ID can leave a
/// group invite for it, sealed with HPKE (CryptoKit, X25519 + ChaCha20-Poly1305) on their
/// phone, so the server can't read the invite. The private key stays in this phone's
/// Keychain. Signing in on a new phone makes a new key; invites sealed to the old one can't
/// be opened there and are dropped.
@MainActor
@Observable
final class Friends {
    enum Failure: Error, Equatable {
        case notSignedIn
        case notFound
        case tooMany
        case offline
        case server
        /// The server doesn't have this feature's tables or functions yet (its SQL file
        /// hasn't been run in Supabase).
        case notSetUp
    }

    struct Received: Identifiable, Sendable {
        let id: UUID
        let payload: FriendInvitePayload
    }

    private(set) var myCode: FriendCode?
    @ObservationIgnored private var myCodeOwner: String?
    @ObservationIgnored private let account: AccountModel
    @ObservationIgnored private let sync: GroupSync
    @ObservationIgnored private var checking = false

    static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let info = Data("takade.friend-invite.v1".utf8)

    init(account: AccountModel, sync: GroupSync) {
        self.account = account
        self.sync = sync
    }

    /// True when this phone is signed in to a TakaDe account on the service.
    var isAvailable: Bool { userID != nil }

    var userID: String? {
        guard let supabase = account.supabase, let session = supabase.session,
              account.profile?.accountID == session.user.id else { return nil }
        return session.user.id
    }

    // MARK: Your ID

    /// Makes this account's ID the first time, and puts this phone's key on it.
    func ensureID() async throws {
        guard let supabase = account.supabase, let user = userID else { throw Failure.notSignedIn }
        if myCodeOwner != user { myCode = nil }
        let key = privateKey(for: user, creating: true)!
        let publicKey = key.publicKey.rawRepresentation.base64URLEncoded
        struct Row: Decodable { let code: String; let public_key: String }
        let data = try await call { try await supabase.rest("friend_id?select=code,public_key", method: "GET") }
        if let row = try JSONDecoder().decode([Row].self, from: data).first, let code = FriendCode(raw: row.code) {
            if row.public_key != publicKey {
                _ = try await call {
                    try await supabase.rest("friend_id?user_id=eq.\(user)", method: "PATCH",
                                            body: ["public_key": publicKey], prefer: "return=minimal")
                }
            }
            setCode(code, for: user)
            return
        }
        for _ in 0..<5 {
            let code = Self.randomCode()
            do {
                _ = try await call {
                    try await supabase.rest("friend_id", method: "POST",
                                            body: ["user_id": user, "code": code.raw, "public_key": publicKey], prefer: "return=minimal")
                }
                setCode(code, for: user)
                return
            } catch SupabaseAuth.Failure.server(_, let code) where code == "23505" {
                // Someone already has that ID (rare at 40 bits): pick another.
            }
        }
        throw Failure.server
    }

    /// A new ID. The old one stops working at once; invites already waiting still arrive.
    func replaceID() async throws {
        guard let supabase = account.supabase, let user = userID else { throw Failure.notSignedIn }
        for _ in 0..<5 {
            let code = Self.randomCode()
            do {
                _ = try await call {
                    try await supabase.rest("friend_id?user_id=eq.\(user)", method: "PATCH",
                                            body: ["code": code.raw], prefer: "return=minimal")
                }
                setCode(code, for: user)
                return
            } catch SupabaseAuth.Failure.server(_, let code) where code == "23505" {
                continue
            }
        }
        throw Failure.server
    }

    private func setCode(_ code: FriendCode, for user: String) {
        myCode = code
        myCodeOwner = user
    }

    // MARK: Sending

    /// The friend's public key, or `notFound`. Each lookup counts toward an hourly limit.
    func lookUp(_ code: FriendCode) async throws -> Curve25519.KeyAgreement.PublicKey {
        guard let supabase = account.supabase, userID != nil else { throw Failure.notSignedIn }
        struct Row: Decodable { let public_key: String }
        let data = try await call { try await supabase.rest("rpc/find_friend", method: "POST", body: ["p_code": code.raw]) }
        guard let text = try JSONDecoder().decode([Row].self, from: data).first?.public_key,
              let raw = Data(base64URLEncoded: text),
              let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else { throw Failure.notFound }
        return key
    }

    func send(_ payload: FriendInvitePayload, to code: FriendCode, key: Curve25519.KeyAgreement.PublicKey) async throws {
        guard let supabase = account.supabase, userID != nil else { throw Failure.notSignedIn }
        let sealed = try Self.seal(JSONEncoder().encode(payload), to: key)
        _ = try await call {
            try await supabase.rest("rpc/send_friend_invite", method: "POST", body: ["p_code": code.raw, "p_sealed": sealed])
        }
    }

    // MARK: Receiving

    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The invite in the join sheet now, and ones closed with Cancel while the app stayed open.
    @ObservationIgnored private var offered: UUID?
    @ObservationIgnored private var snoozed: Set<UUID> = []

    /// The join sheet closed. Joined or declined invites are already gone from the server;
    /// one closed with Cancel isn't offered again until the app is next opened.
    func offerClosed() async {
        if let offered { snoozed.insert(offered) }
        offered = nil
        await checkInbox()
    }

    static let checkEvery: Duration = .seconds(15)

    /// While the app is open: publishes this device's key once (so senders seal to a key it
    /// has), then looks for invites every 15 seconds. A plain request each time, with no
    /// always-on connection, so it stays within the free plan. Stops in the background.
    func startWatching() {
        guard watching == nil else { return }
        // Invites put off with Cancel come back the next time the app is opened.
        snoozed = []
        watching = Task { [weak self] in
            if let self, self.isAvailable { try? await self.ensureID() }
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkInbox()
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    /// Looks for invites left for this account and offers the first new one in the join
    /// sheet. Runs every 15 seconds while the app is open.
    func checkInbox() async {
        guard !checking, sync.pendingInvite == nil, let supabase = account.supabase, let user = userID,
              let key = privateKey(for: user, creating: false) else { return }
        checking = true
        defer { checking = false }
        struct Row: Decodable { let id: UUID; let sealed: String }
        guard let data = try? await supabase.rest("friend_invite?select=id,sealed&order=created_at.desc&limit=50", method: "GET"),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
        if !rows.isEmpty { await sync.loadStates() }
        for row in rows where !snoozed.contains(row.id) {
            guard let plain = try? Self.open(row.sealed, with: key),
                  let payload = try? JSONDecoder().decode(FriendInvitePayload.self, from: plain),
                  // Anyone who knows this account's ID can leave an invite, so its names are
                  // untrusted: oversized ones are dropped rather than shown.
                  payload.fromName.count <= SyncLimits.maxPersonNameLength,
                  payload.groupName.count <= SyncLimits.maxGroupNameLength, payload.link.count <= 1_000,
                  let url = URL(string: payload.link), let invite = GroupInvite(url: url) else {
                // Not readable here: sealed to a key this device doesn't have yet (iCloud
                // Keychain may still be bringing it over) or damaged. Left for the person's
                // other device; the server drops it after 7 days.
                continue
            }
            if sync.isShared(invite.groupID) {
                // Already in the group on this phone.
                await remove(row.id)
                continue
            }
            offered = row.id
            sync.pendingInvite = PendingInvite(invite: invite, from: Received(id: row.id, payload: payload))
            return
        }
    }

    /// Joined or declined: the invite is no longer needed on the server.
    func remove(_ id: UUID) async {
        _ = try? await account.supabase?.rest("friend_invite?id=eq.\(id.uuidString)", method: "DELETE", prefer: "return=minimal")
    }

    // MARK: Keys and sealing

    /// The account's key, shared by the person's iPhone and iPad through iCloud Keychain, so
    /// whichever device opens TakaDe can read what was sent. Before, each device made its
    /// own key and the last one opened replaced the other's on the server, so invites and
    /// messages sealed for one device were unreadable (and dropped) on the other.
    func privateKey(for user: String, creating: Bool) -> Curve25519.KeyAgreement.PrivateKey? {
        let name = "friend.key.\(user)"
        if let key = KeychainStore.getSynced(name).flatMap(Self.key(from:)) { return key }
        // A key from an earlier version, on this device only: move it to the synced item.
        if let key = KeychainStore.get(name).flatMap(Self.key(from:)) {
            KeychainStore.setSynced(key.rawRepresentation.base64URLEncoded, for: name)
            if KeychainStore.getSynced(name) != nil { KeychainStore.delete(name) }
            return key
        }
        guard creating else { return nil }
        let key = Curve25519.KeyAgreement.PrivateKey()
        KeychainStore.setSynced(key.rawRepresentation.base64URLEncoded, for: name)
        // iCloud Keychain can refuse (rare); keep it on this device then.
        if KeychainStore.getSynced(name) == nil { KeychainStore.set(key.rawRepresentation.base64URLEncoded, for: name) }
        return key
    }

    private static func key(from text: String) -> Curve25519.KeyAgreement.PrivateKey? {
        Data(base64URLEncoded: text).flatMap { try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0) }
    }

    /// "v1." + encapsulated key + "." + ciphertext, both base64url.
    static func seal(_ plain: Data, to key: Curve25519.KeyAgreement.PublicKey) throws -> String {
        var sender = try HPKE.Sender(recipientKey: key, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(plain)
        return "v1." + sender.encapsulatedKey.base64URLEncoded + "." + ciphertext.base64URLEncoded
    }

    static func open(_ sealed: String, with key: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let parts = sealed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "v1", let encapsulated = Data(base64URLEncoded: String(parts[1])),
              let ciphertext = Data(base64URLEncoded: String(parts[2])) else { throw Failure.server }
        var recipient = try HPKE.Recipient(privateKey: key, ciphersuite: suite, info: info, encapsulatedKey: encapsulated)
        return try recipient.open(ciphertext)
    }

    private static func randomCode() -> FriendCode {
        var bytes = [UInt8](repeating: 0, count: 5)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return FriendCode(randomBytes: bytes)
    }


    /// Turns service and network errors into the few cases the screens explain.
    func call(_ body: () async throws -> Data) async throws -> Data {
        do {
            return try await body()
        } catch SupabaseAuth.Failure.notSignedIn {
            throw Failure.notSignedIn
        } catch SupabaseAuth.Failure.server(let status, let code) {
            if code == "TK429" { throw Failure.tooMany }
            if code == "P0002" { throw Failure.notFound }
            if code == "28000" || status == 401 { throw Failure.notSignedIn }
            // PostgREST: no such function or table. Postgres: undefined function or table.
            if code == "PGRST202" || code == "PGRST205" || code == "42883" || code == "42P01" { throw Failure.notSetUp }
            if code == "23505" { throw SupabaseAuth.Failure.server(status: status, code: code) }
            throw Failure.server
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                throw Failure.offline
            default:
                throw Failure.server
            }
        }
    }
}

extension Friends.Failure {
    var message: String {
        switch self {
        case .notSignedIn:
            String(localized: "Sign in to your TakaDe account to use TakaDe IDs.", bundle: .appLanguage)
        case .notFound:
            String(localized: "No one has this TakaDe ID. Check it and try again.", bundle: .appLanguage)
        case .tooMany:
            String(localized: "Too many tries for now. Wait a while and try again.", bundle: .appLanguage)
        case .offline:
            String(localized: "You're offline. Connect to the internet and try again.", bundle: .appLanguage)
        case .server:
            String(localized: "Something went wrong. Try again in a moment.", bundle: .appLanguage)
        case .notSetUp:
            String(localized: "TakaDe's server isn't ready for this yet. Try again later.", bundle: .appLanguage)
        }
    }

    static func message(for error: Error) -> String {
        if let failure = error as? Friends.Failure { return failure.message }
        return SharingError.message(for: error)
    }
}
