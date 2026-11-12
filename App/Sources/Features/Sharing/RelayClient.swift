import Foundation
import TakaDeCore
import UIKit

/// The encrypted relay on Supabase (supabase/migrations/20261112000000_shared_groups.sql),
/// over its REST API with URLSession, like SupabaseAuth: no Supabase SDK.
///
/// Sharing uses its own sign-in, separate from the TakaDe account: an anonymous Supabase
/// user made the first time this phone shares or joins. Friends can join without an
/// account, and the relay can't link a group to anyone's email or name.
actor RelayClient {
    enum Failure: Error, Equatable {
        case offline
        case inviteNotValid
        /// The group is gone from the relay (idle for a year) or this phone was never in it.
        case notInGroup
        case guestSignInOff
        case server(status: Int, code: String?)
    }

    struct Row: Decodable, Sendable {
        let seq: Int64
        let change_id: UUID
        let ciphertext: String
    }

    private struct Session: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var isExpiring: Bool { expiresAt.timeIntervalSinceNow < 60 }
    }

    private static let sessionKey = "relay.session"
    private let config: SupabaseConfig
    private var session: Session?
    private var signingIn: Task<Session, Error>?
    /// Set when the old sharing sign-in couldn't be refreshed and a new guest sign-in took
    /// its place. The phone then has to rejoin its groups with their rejoin secrets.
    private var replacedSignIn = false

    init(config: SupabaseConfig) {
        self.config = config
        session = SyncKeychain.get(Self.sessionKey).flatMap { try? JSONDecoder().decode(Session.self, from: Data($0.utf8)) }
    }

    private var restURL: URL { config.baseURL.appendingPathComponent("rest/v1") }

    // MARK: Groups and invites

    /// Registers a group on the relay; this phone becomes its first member. Doing it twice is fine.
    func createGroup(_ id: GroupID) async throws {
        do {
            _ = try await send("sync_group", method: "POST", body: ["id": id.description], prefer: "return=minimal")
        } catch Failure.server(let status, _) where status == 409 {
            // Already there from an earlier try.
        }
    }

    func createInvite(for group: GroupID, tokenHash: String, expiresAt: Date) async throws {
        let body: [String: Any] = ["token_hash": tokenHash, "group_id": group.description,
                                   "expires_at": ISO8601DateFormatter().string(from: expiresAt)]
        _ = try await send("sync_invite", method: "POST", body: body, prefer: "return=minimal")
    }

    /// Stops every link to the group made so far. People already in the group stay in.
    func stopInvites(for group: GroupID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await send("sync_invite?group_id=eq.\(group)&revoked_at=is.null", method: "PATCH",
                           body: ["revoked_at": now], prefer: "return=minimal")
    }

    /// Joins with an invite token and returns the group it's for.
    func join(token: String) async throws -> GroupID {
        let data: Data
        do {
            data = try await send("rpc/join_sync_group", method: "POST", body: ["p_token": token])
        } catch Failure.server(let status, let code) where code == "P0002" || status == 404 {
            throw Failure.inviteNotValid
        }
        guard let text = try? JSONDecoder().decode(String.self, from: data), let id = UUID(uuidString: text) else {
            throw Failure.server(status: 200, code: nil)
        }
        return GroupID(id)
    }

    func isMember(of group: GroupID) async throws -> Bool {
        let data = try await send("sync_group?id=eq.\(group)&select=id", method: "GET", body: nil)
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
        return !rows.isEmpty
    }

    /// Every shared group this sign-in is in, with the server time of its last change. One
    /// request for all groups, so the once-a-minute check doesn't ask about each group.
    func groupStamps() async throws -> [GroupID: String] {
        struct Stamp: Decodable { let id: UUID; let last_change_at: String }
        let data = try await send("sync_group?select=id,last_change_at", method: "GET", body: nil)
        let rows = try JSONDecoder().decode([Stamp].self, from: data)
        return Dictionary(rows.map { (GroupID($0.id), $0.last_change_at) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stores the hash of this phone's rejoin secret on its member row
    /// (supabase/migrations/20261112070000_ready_for_10k.sql). False when not in the group.
    func setRejoin(_ group: GroupID, hash: String) async throws -> Bool {
        let data = try await send("rpc/set_sync_rejoin", method: "POST", body: ["p_group": group.description, "p_hash": hash])
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    /// Moves this phone's old member row to the current sign-in. False when nothing matches.
    func rejoin(_ group: GroupID, secret: String) async throws -> Bool {
        let data = try await send("rpc/rejoin_sync_group", method: "POST", body: ["p_group": group.description, "p_secret": secret])
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    /// True once after the sharing sign-in was replaced by a new one.
    func takeReplacedSignIn() -> Bool {
        defer { replacedSignIn = false }
        return replacedSignIn
    }

    func leave(_ group: GroupID) async throws {
        let user = try await currentSession().userID
        _ = try await send("sync_member?group_id=eq.\(group)&user_id=eq.\(user)", method: "DELETE", body: nil, prefer: "return=minimal")
    }

    // MARK: Changes

    /// Uploads sealed changes. A change already on the relay (a retry) is skipped there.
    func push(_ items: [(id: UUID, ciphertext: String)], to group: GroupID) async throws {
        guard !items.isEmpty else { return }
        let body = items.map { ["change_id": $0.id.uuidString, "group_id": group.description, "ciphertext": $0.ciphertext] }
        do {
            _ = try await send("sync_change?on_conflict=change_id", method: "POST", body: body,
                               prefer: "resolution=ignore-duplicates,return=minimal")
        } catch Failure.server(let status, let code) where status == 403 || code == "42501" || code == "23503" {
            throw Failure.notInGroup
        }
    }

    func pull(_ group: GroupID, after cursor: Int64, limit: Int) async throws -> [Row] {
        let path = "sync_change?group_id=eq.\(group)&seq=gt.\(cursor)&order=seq.asc&limit=\(limit)&select=seq,change_id,ciphertext"
        let data = try await send(path, method: "GET", body: nil)
        return try JSONDecoder().decode([Row].self, from: data)
    }

    // MARK: Bundles (supabase/migrations/20261112080000_pack_old_changes.sql)

    struct Bundle: Decodable, Sendable {
        let id: UUID
        let through_seq: Int64
        let ciphertext: String
    }

    struct PackPoint: Decodable, Sendable {
        let through_seq: Int64?
        let packable: Int64
        let packed_at: String?
    }

    /// The group's packed bundle, only if it covers changes after `cursor`. Nil when there
    /// is none to read.
    func bundle(_ group: GroupID, after cursor: Int64) async throws -> Bundle? {
        let data = try await send("sync_bundle?group_id=eq.\(group)&through_seq=gt.\(cursor)&select=id,through_seq,ciphertext",
                                  method: "GET", body: nil)
        return try JSONDecoder().decode([Bundle].self, from: data).first
    }

    /// Just the id of the group's bundle when it covers changes after `cursor`, without its
    /// content.
    func bundleID(_ group: GroupID, after cursor: Int64) async throws -> UUID? {
        struct Header: Decodable { let id: UUID }
        let data = try await send("sync_bundle?group_id=eq.\(group)&through_seq=gt.\(cursor)&select=id", method: "GET", body: nil)
        return try JSONDecoder().decode([Header].self, from: data).first?.id
    }

    /// Where a pack of the group could end now, and how many rows it would remove.
    func packPoint(_ group: GroupID) async throws -> PackPoint? {
        let data = try await send("rpc/sync_pack_point", method: "POST", body: ["p_group": group.description])
        return try JSONDecoder().decode([PackPoint].self, from: data).first
    }

    /// Uploads a bundle; the relay then deletes the rows it covers. False when the relay
    /// turned it down (packed recently, or the position is no longer valid).
    func pack(_ group: GroupID, id: UUID, through: Int64, ciphertext: String) async throws -> Bool {
        let data = try await send("rpc/pack_sync_group", method: "POST",
                                  body: ["p_group": group.description, "p_id": id.uuidString, "p_through": through, "p_ciphertext": ciphertext])
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    // MARK: Receipt photos

    func hasReceipt(_ id: UUID) async throws -> Bool {
        let data = try await send("sync_receipt?id=eq.\(id.uuidString)&select=id", method: "GET", body: nil)
        return !(((try? JSONSerialization.jsonObject(with: data)) as? [Any]) ?? []).isEmpty
    }

    func uploadReceipt(_ id: UUID, ciphertext: String, to group: GroupID) async throws {
        let body: [String: Any] = ["id": id.uuidString, "group_id": group.description, "ciphertext": ciphertext]
        do {
            _ = try await send("sync_receipt?on_conflict=id", method: "POST", body: body, prefer: "resolution=ignore-duplicates,return=minimal")
        } catch Failure.server(let status, let code) where status == 403 || code == "42501" || code == "23503" {
            throw Failure.notInGroup
        }
    }

    /// Nil when the relay doesn't have it (not uploaded yet, or the group was cleaned up).
    func downloadReceipt(_ id: UUID, in group: GroupID) async throws -> String? {
        struct Row: Decodable { let ciphertext: String }
        let data = try await send("sync_receipt?id=eq.\(id.uuidString)&group_id=eq.\(group)&select=ciphertext", method: "GET", body: nil)
        return try JSONDecoder().decode([Row].self, from: data).first?.ciphertext
    }

    /// For "Delete all my data": leaves nothing to sign in with.
    func forget() {
        session = nil
        SyncKeychain.delete(Self.sessionKey)
    }

    // MARK: Requests

    private func send(_ path: String, method: String, body: Any?, prefer: String? = nil, retried: Bool = false) async throws -> Data {
        guard let url = URL(string: restURL.absoluteString + "/" + path) else { throw Failure.server(status: 0, code: nil) }
        let token = try await currentSession().accessToken
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await load(request)
        guard (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let code = json["code"] as? String
            // An expired token: refresh once (or, if the guest user was cleaned up, start a
            // new one) and try again.
            if response.statusCode == 401 || code == "PGRST301" || code == "PGRST303", !retried {
                session?.expiresAt = .distantPast
                return try await send(path, method: method, body: body, prefer: prefer, retried: true)
            }
            throw Failure.server(status: response.statusCode, code: code)
        }
        return data
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.server(status: 0, code: nil) }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .dataNotAllowed, .internationalRoamingOff:
                throw Failure.offline
            default:
                throw error
            }
        }
    }

    // MARK: Sign-in

    private func currentSession() async throws -> Session {
        // "Delete all my data" clears the Keychain; don't keep using the old sign-in.
        if session != nil, SyncKeychain.get(Self.sessionKey) == nil { session = nil }
        if let session, !session.isExpiring { return session }
        if let signingIn { return try await signingIn.value }
        let previous = session
        let task = Task { try await self.signIn(refreshing: previous) }
        signingIn = task
        defer { signingIn = nil }
        let fresh = try await task.value
        session = fresh
        if let data = try? JSONEncoder().encode(fresh), let text = String(data: data, encoding: .utf8) {
            SyncKeychain.set(text, for: Self.sessionKey)
        }
        return fresh
    }

    private func signIn(refreshing previous: Session?) async throws -> Session {
        // The service retires a refresh token as soon as it answers, so finish the request
        // (and the Keychain save after it) even if the app goes to the background meanwhile.
        let background = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "Sharing sign-in") }
        defer {
            if background != .invalid { Task { @MainActor in UIApplication.shared.endBackgroundTask(background) } }
        }
        if let previous {
            let body = ["refresh_token": previous.refreshToken]
            do {
                do {
                    return try await auth("token?grant_type=refresh_token", body: body)
                } catch Failure.offline {
                    // The answer may have been lost after the service used the token up. A
                    // quick repeat gets the same new tokens instead of a refusal.
                    return try await auth("token?grant_type=refresh_token", body: body)
                }
            } catch Failure.server(let status, _) where (400...401).contains(status) {
                // Refresh token used up or the guest user was cleaned up: start a new one,
                // and let GroupSync move this phone's memberships over to it.
                replacedSignIn = true
            }
        }
        do {
            return try await auth("signup", body: [:])
        } catch Failure.server(let status, _) where (400...422).contains(status) {
            throw Failure.guestSignInOff
        }
    }

    private func auth(_ path: String, body: [String: Any]) async throws -> Session {
        guard let url = URL(string: config.authURL.absoluteString + "/" + path) else { throw Failure.server(status: 0, code: nil) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await load(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.server(status: response.statusCode, code: (json["error_code"] as? String) ?? (json["code"] as? String))
        }
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = (json["user"] as? [String: Any])?["id"] as? String else { throw Failure.server(status: response.statusCode, code: nil) }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        return Session(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn), userID: user)
    }
}
