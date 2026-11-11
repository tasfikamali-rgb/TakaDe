import CryptoKit
import Foundation
import Observation
import TakaDeCore

/// A link that was tapped or pasted, waiting for the join sheet.
struct PendingInvite: Identifiable {
    let id = UUID()
    let invite: GroupInvite
}

/// Shared groups (docs/adr/0018-shared-groups.md). The phone stays the source of truth:
/// every change is saved to SQLite first, then sealed with the group's key and sent to the
/// relay. Changes from other phones are pulled, opened and applied in the relay's order.
/// Without Supabase configured (or offline), groups keep working on the phone alone.
@MainActor
@Observable
final class GroupSync {
    enum Status: Equatable {
        case syncing
        case upToDate
        /// Changes are saved here and go up when the phone is back online.
        case offline
        /// The relay removed the group after 90 days with no changes. It stays on this phone.
        case ended
        case failed
    }

    enum Failure: Error {
        case unavailable
        case wrongGroup
    }

    static let inviteLifetime: TimeInterval = 7 * 24 * 3600

    private(set) var states: [GroupID: SharedGroupState] = [:]
    private(set) var status: [GroupID: Status] = [:]
    var pendingInvite: PendingInvite?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let relay: RelayClient?
    @ObservationIgnored private var running: [GroupID: Task<Void, Error>] = [:]
    @ObservationIgnored private var scheduled: Set<GroupID> = []

    var isAvailable: Bool { relay != nil }

    init(app: AppModel, config: SupabaseConfig? = .current) {
        self.app = app
        relay = config.map(RelayClient.init(config:))
        app.onLocalChange = { [weak self] group in self?.scheduleSync(group) }
    }

    func isShared(_ group: GroupID) -> Bool { states[group] != nil }

    func loadStates() async {
        guard let list = try? await app.syncStore.sharedGroups() else { return }
        states = Dictionary(uniqueKeysWithValues: list.map { ($0.groupID, $0) })
    }

    // MARK: Invite

    /// Shares the group if it isn't yet (uploading everything in it so far), then makes a
    /// new invite link that works for 7 days.
    func inviteLink(for group: ExpenseGroup) async throws -> URL {
        guard let relay else { throw Failure.unavailable }
        if (try await app.syncStore.sharedState(of: group.id)) == nil {
            if SyncKeychain.key(for: group.id) == nil { SyncKeychain.setKey(SyncCipher.newKey(), for: group.id) }
            try await relay.createGroup(group.id)
            try await app.syncStore.startSharing(group.id)
            await loadStates()
        }
        guard let key = SyncKeychain.key(for: group.id) else { throw Failure.unavailable }
        // Everything is on the relay before the link exists, so a friend never opens an empty group.
        try await syncNow(group.id)
        let token = Self.randomToken()
        let hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        try await relay.createInvite(for: group.id, tokenHash: hash, expiresAt: Date().addingTimeInterval(Self.inviteLifetime))
        let keyData = key.withUnsafeBytes { Data($0) }
        guard let invite = GroupInvite(groupID: group.id, token: token, key: keyData) else { throw Failure.unavailable }
        return invite.url
    }

    func stopLinks(for group: GroupID) async throws {
        guard let relay else { throw Failure.unavailable }
        try await relay.stopInvites(for: group)
    }

    // MARK: Join

    /// Joins with a link and brings the whole group onto this phone.
    func join(_ invite: GroupInvite) async throws -> GroupID {
        guard let relay else { throw Failure.unavailable }
        let id = try await relay.join(token: invite.token)
        guard id == invite.groupID else { throw Failure.wrongGroup }
        SyncKeychain.setKey(SymmetricKey(data: invite.key), for: id)
        try await app.syncStore.prepareToJoin(id)
        await loadStates()
        try await syncNow(id)
        await app.reload()
        return id
    }

    // MARK: Syncing

    /// Syncs every shared group: on launch and when the app comes back.
    func syncAll() async {
        await loadStates()
        for id in states.keys { await sync(id) }
    }

    /// Syncs one group, recording the outcome for the group screen instead of throwing.
    func sync(_ group: GroupID) async {
        do {
            try await syncNow(group)
        } catch RelayClient.Failure.offline {
            status[group] = .offline
        } catch RelayClient.Failure.notInGroup {
            await handleRemoved(group)
        } catch is CancellationError {
            // Left the screen; the next sync picks up from the same place.
        } catch {
            status[group] = .failed
        }
    }

    /// A local edit: sync soon, once, even after several quick edits.
    private func scheduleSync(_ group: GroupID) {
        guard relay != nil, states[group] != nil, !scheduled.contains(group) else { return }
        scheduled.insert(group)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            scheduled.remove(group)
            await sync(group)
        }
    }

    /// One sync at a time per group. A request that arrives mid-sync waits for it and then
    /// runs again, so its own changes aren't missed.
    private func syncNow(_ group: GroupID) async throws {
        if let current = running[group] { _ = try? await current.value }
        let task = Task { try await self.pushAndPull(group) }
        running[group] = task
        defer { if running[group] == task { running[group] = nil } }
        try await task.value
    }

    private func pushAndPull(_ group: GroupID) async throws {
        guard let relay, (try await app.syncStore.sharedState(of: group)) != nil else { return }
        guard let key = SyncKeychain.key(for: group) else {
            status[group] = .failed
            return
        }
        status[group] = .syncing
        let store = app.syncStore

        // Up: this phone's changes, oldest first.
        while true {
            let pending = try await store.pendingChanges(in: group, limit: 100)
            guard !pending.isEmpty else { break }
            let sealed = try pending.map { (id: $0.id, ciphertext: try SyncCipher.seal($0, with: key)) }
            try await relay.push(sealed, to: group)
            try await store.markUploaded(pending.map(\.id))
        }

        // Down: everything after this phone's place in the group's order.
        var applied = 0
        let pageSize = 200
        while true {
            let cursor = try await store.sharedState(of: group)?.cursor ?? 0
            let rows = try await relay.pull(group, after: cursor, limit: pageSize)
            guard let last = rows.last else { break }
            // A change that can't be opened (wrong key, damaged) is skipped, never applied.
            let received = rows.compactMap { row in
                (try? SyncCipher.open(row.ciphertext, changeID: row.change_id, groupID: group, with: key))
                    .map { ReceivedChange(sequence: row.seq, change: $0) }
            }
            let result = try await store.apply(received, through: last.seq, in: group, syncedAt: Date())
            applied += result.applied
            if rows.count < pageSize { break }
        }
        try await store.markSynced(group, at: Date())
        if applied > 0 { await app.reload() }
        await loadStates()
        status[group] = .upToDate
    }

    /// The relay no longer has the group. Keep everything on the phone and say so.
    private func handleRemoved(_ group: GroupID) async {
        guard let relay, let member = try? await relay.isMember(of: group), !member else {
            status[group] = .failed
            return
        }
        try? await app.syncStore.stopSharing(group)
        SyncKeychain.removeKey(for: group)
        await loadStates()
        status[group] = .ended
    }

    // MARK: Who am I

    func choose(_ member: MemberID, in group: GroupID) async throws {
        try await app.syncStore.setMe(member, in: group)
        await app.reload()
    }

    /// "I'm not on the list": adds the person to the group (sent to everyone) as this phone's "me".
    func addMe(named name: String, to group: ExpenseGroup) async throws {
        let me = Member(displayName: name)
        var updated = app.group(group.id) ?? group
        updated.members.append(me)
        try await app.repository.save(updated, actor: me.id)
        try await app.syncStore.setMe(me.id, in: group.id)
        await app.reload()
        scheduleSync(group.id)
    }

    private static func randomToken() -> String {
        var bytes = Data(count: 32)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        return bytes.base64URLEncoded
    }
}
