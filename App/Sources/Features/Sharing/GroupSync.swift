import CoreGraphics
import CryptoKit
import Foundation
import Observation
import TakaDeCore

/// A link that was tapped or pasted, waiting for the join sheet.
struct PendingInvite: Identifiable {
    let id = UUID()
    let invite: GroupInvite
    /// Set when a friend sent it to this account by TakaDe ID, not as a link.
    var from: Friends.Received?
}

/// Shared groups (docs/adr/0019-shared-groups.md). The phone stays the source of truth:
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
        /// The relay removed the group after a year with no changes. It stays on this phone.
        case ended
        case failed
    }

    enum Failure: Error {
        case unavailable
        case wrongGroup
        /// Only the person who made a shared group can delete it for everyone.
        case notOwner
    }

    static let inviteLifetime: TimeInterval = 7 * 24 * 3600

    private(set) var states: [GroupID: SharedGroupState] = [:]
    private(set) var status: [GroupID: Status] = [:]
    var pendingInvite: PendingInvite?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let relay: RelayClient?
    @ObservationIgnored private var running: [GroupID: Task<Void, Error>] = [:]
    @ObservationIgnored private var scheduled: Set<GroupID> = []
    /// Each group's last change on the relay when this phone last synced it, so the
    /// once-a-minute check only syncs groups that changed.
    @ObservationIgnored private var stamps: [GroupID: String] = [:]
    /// The relay doesn't have the rejoin functions yet (migration not run): don't ask again.
    @ObservationIgnored private var rejoinUnavailable = false
    /// The relay doesn't have bundles yet (migration not run): read and pack rows only.
    @ObservationIgnored private var bundlesUnavailable = false
    /// A group is packed once this many of its rows are old enough to pack.
    static let packThreshold: Int64 = 200
    /// Expenses and payments other phones changed, after they're applied here. Not called
    /// for the first download of a group just joined or shared. Used for notifications.
    @ObservationIgnored var onChangesFromOthers: ((GroupID, [AppliedChange]) async -> Void)?

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
        // Rejoining a group already on this phone doesn't add one.
        guard app.canAddGroup || app.group(invite.groupID) != nil else { throw AppModel.GroupLimitReached() }
        let id = try await relay.join(token: invite.token)
        guard id == invite.groupID else { throw Failure.wrongGroup }
        SyncKeychain.setKey(SymmetricKey(data: invite.key), for: id)
        try await app.syncStore.prepareToJoin(id)
        await loadStates()
        try await syncNow(id)
        await app.reload()
        return id
    }

    // MARK: Delete

    /// Deletes a group. A shared group is deleted for everyone: a sealed "deleted" change goes
    /// to the relay first, so the other phones delete it when they next sync, then this phone
    /// leaves the relay group (the relay drops it once the last phone has left). Needs the
    /// internet for a shared group; nothing is deleted if the change can't be sent.
    func deleteGroup(_ group: ExpenseGroup) async throws {
        if (try await app.syncStore.sharedState(of: group.id)) != nil {
            guard let relay, let key = SyncKeychain.key(for: group.id) else { throw Failure.unavailable }
            guard let me = group.me?.id, me == group.ownerID else { throw Failure.notOwner }
            // Let a sync already running finish, so nothing is half applied.
            if let current = running[group.id] { _ = try? await current.value }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let change = SyncChange(groupID: group.id, entity: .groupDeleted,
                                    body: try encoder.encode(GroupDeletion(groupID: group.id, deletedBy: me)))
            do {
                try await relay.push([(id: change.id, ciphertext: try SyncCipher.seal(change, with: key))], to: group.id)
                try? await relay.leave(group.id)
            } catch RelayClient.Failure.notInGroup {
                // The relay already dropped the group (a year idle): nobody else to tell.
            }
            SyncKeychain.removeKey(for: group.id)
        }
        try await app.deleteGroup(group.id)
        status[group.id] = nil
        await loadStates()
    }

    /// The group's maker deleted it on their phone and it's now gone from this one too.
    private func finishRemoteDeletion(_ group: GroupID, files: AppModel.GroupFiles?) async {
        try? await relay?.leave(group)
        SyncKeychain.removeKey(for: group)
        if let files { app.removeFiles(files) }
        GroupPhotoFile.remove(group)
        status[group] = nil
        await app.reload()
        await loadStates()
    }

    // MARK: Syncing

    /// Syncs every shared group: on launch and when the app comes back.
    func syncAll() async {
        await loadStates()
        // The app moved to the other project (ServerSwitch): it may be missing the last day's
        // changes, so every shared group goes up again whole. Repeats are stored once per id
        // and newer versions win, so nothing is applied twice.
        if ServerSwitch.takeChanged() {
            for id in states.keys { try? await app.syncStore.requeueEverything(id) }
            await loadStates()
        }
        for id in states.keys { await sync(id) }
    }

    /// The once-a-minute check, and the check when the app comes back: one request for all
    /// groups, then a sync only for groups that changed on the relay, have changes waiting on
    /// this phone, or failed last time. Falls back to syncing everything.
    func syncChanged() async {
        guard let relay else { return }
        await loadStates()
        await rejoinIfSignInReplaced()
        let known = Array(states.keys)
        guard !known.isEmpty else { return }
        guard let current = try? await relay.groupStamps() else {
            for id in known { await sync(id) }
            return
        }
        for id in known {
            guard let stamp = current[id] else {
                // Not visible to this sign-in: rejoin, or the relay dropped the group.
                await handleRemoved(id)
                continue
            }
            let waiting = !((try? await app.syncStore.pendingChanges(in: id, limit: 1)) ?? []).isEmpty
            if waiting || stamps[id] != stamp || status[id] != .upToDate {
                await sync(id)
                if status[id] == .upToDate, !waiting { stamps[id] = stamp }
            }
        }
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
        await rejoinIfSignInReplaced()
        guard let key = SyncKeychain.key(for: group) else {
            status[group] = .failed
            return
        }
        status[group] = .syncing
        let store = app.syncStore

        // Up: this phone's changes, oldest first. A receipt photo goes up before the expense
        // that points to it, so nobody sees an expense whose photo isn't there yet.
        while true {
            let pending = try await store.pendingChanges(in: group, limit: 100)
            guard !pending.isEmpty else { break }
            try await uploadReceipts(for: pending, in: group, key: key)
            let sealed = try pending.map { (id: $0.id, ciphertext: try SyncCipher.seal($0, with: key)) }
            try await relay.push(sealed, to: group)
            try await store.markUploaded(pending.map(\.id))
        }

        // Down: everything after this phone's place in the group's order.
        var applied = 0
        var fromOthers: [AppliedChange] = []
        // Cursor 0 means the whole group is arriving for the first time: nothing to announce.
        let startedAt = try await store.sharedState(of: group)?.cursor ?? 0
        // Older changes may have been packed into one bundle. A phone that hasn't seen them
        // yet (just joined, or away a while) reads the bundle first, then the rows after it.
        // If another phone packed the group while this one was paging through it, some rows
        // vanished mid-download: go back to where this sync started and read the new bundle.
        for attempt in 0..<2 {
            if attempt > 0 { try await store.rewind(group, to: startedAt) }
            let read = try await applyBundleIfBehind(group, cursor: startedAt, key: key)
            if let result = read?.result {
                applied += result.applied
                fromOthers += result.fromOthers
            }
            let pageSize = 200
            var pages = 0
            while true {
                let cursor = try await store.sharedState(of: group)?.cursor ?? 0
                let rows = try await relay.pull(group, after: cursor, limit: pageSize)
                pages += 1
                guard let last = rows.last else { break }
                // A change that can't be opened (wrong key, damaged) is skipped, never applied.
                let received = rows.compactMap { row in
                    (try? SyncCipher.open(row.ciphertext, changeID: row.change_id, groupID: group, with: key))
                        .map { ReceivedChange(sequence: row.seq, change: $0) }
                }
                // If the maker deleted the group, note its photos first: the ledger rows that point
                // to them are deleted along with the group.
                let files = received.contains { $0.change.entity == .groupDeleted } ? await app.files(of: group) : nil
                let result = try await store.apply(received, through: last.seq, in: group, syncedAt: Date())
                if result.groupDeleted {
                    await finishRemoteDeletion(group, files: files)
                    return
                }
                applied += result.applied
                fromOthers += result.fromOthers
                if rows.count < pageSize { break }
            }
            guard pages > 1, await packedDuringDownload(group, since: startedAt, alreadyRead: read?.id) else { break }
        }
        try await store.markSynced(group, at: Date())
        if applied > 0 { await app.reload() }
        await loadStates()
        status[group] = .upToDate
        if startedAt > 0, !fromOthers.isEmpty { await onChangesFromOthers?(group, fromOthers) }
        await registerRejoinSecret(group)
        await packIfWorthIt(group, key: key)
    }

    // MARK: Bundles (docs/adr/0034-packed-changes-and-backups.md)

    /// Reads and applies the group's bundle when it covers changes after `cursor`. Returns the
    /// bundle's id and what changed, or nil when there was nothing to read.
    private func applyBundleIfBehind(_ group: GroupID, cursor: Int64, key: SymmetricKey) async throws -> (id: UUID, result: ApplyResult)? {
        guard let relay, !bundlesUnavailable else { return nil }
        let bundle: RelayClient.Bundle?
        do {
            bundle = try await relay.bundle(group, after: cursor)
        } catch RelayClient.Failure.server(let status, let code) where Self.isMissingOnRelay(status: status, code: code) {
            bundlesUnavailable = true
            return nil
        }
        guard let bundle else { return nil }
        // A bundle that can't be opened stops the sync (status "failed") instead of skipping
        // it: the rows it replaced are gone, so skipping would silently lose them.
        let changes = try SyncCipher.openBundle(bundle.ciphertext, id: bundle.id, through: bundle.through_seq, groupID: group, with: key)
        return (id: bundle.id, result: try await app.syncStore.applyBundle(changes, through: bundle.through_seq, in: group, syncedAt: Date()))
    }

    /// True when a bundle other than the one already read now covers changes after `start`.
    private func packedDuringDownload(_ group: GroupID, since start: Int64, alreadyRead: UUID?) async -> Bool {
        guard let relay, !bundlesUnavailable, let latest = try? await relay.bundleID(group, after: start) else { return false }
        return latest != alreadyRead
    }

    /// Once a day per group, after a full sync with nothing waiting to go up: if enough of the
    /// group's rows are old enough, seal the whole group into one bundle and let the relay
    /// replace those rows with it. Any member's phone can do it; the relay takes one pack per
    /// group every 6 hours.
    private func packIfWorthIt(_ group: GroupID, key: SymmetricKey) async {
        guard let relay, !bundlesUnavailable else { return }
        let checkedKey = "sync.packChecked.\(group)"
        if let last = UserDefaults.standard.object(forKey: checkedKey) as? Date, Date().timeIntervalSince(last) < 24 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: checkedKey)
        do {
            guard let point = try await relay.packPoint(group), let through = point.through_seq,
                  point.packable >= Self.packThreshold,
                  let state = try await app.syncStore.sharedState(of: group),
                  // This phone has everything up to that point and nothing still to upload.
                  state.cursor >= through, state.pendingUploads == 0 else { return }
            let changes = try await app.syncStore.bundleChanges(of: group)
            let id = UUID()
            let sealed = try SyncCipher.sealBundle(changes, id: id, through: through, groupID: group, with: key)
            _ = try await relay.pack(group, id: id, through: through, ciphertext: sealed)
        } catch RelayClient.Failure.server(let status, let code) where Self.isMissingOnRelay(status: status, code: code) {
            bundlesUnavailable = true
        } catch {
            // Tried again tomorrow.
        }
    }

    /// The relay answered "no such table or function": its migration hasn't been run yet.
    private static func isMissingOnRelay(status: Int, code: String?) -> Bool {
        status == 404 || ["PGRST202", "PGRST205", "42883", "42P01"].contains(code ?? "")
    }

    // MARK: Rejoin (supabase/migrations/20261112070000_ready_for_10k.sql)

    /// Gives this phone a rejoin secret for the group once, so a lost sharing sign-in
    /// doesn't drop it out of the group.
    private func registerRejoinSecret(_ group: GroupID) async {
        guard let relay, !rejoinUnavailable, SyncKeychain.rejoinSecret(for: group) == nil else { return }
        let secret = Self.randomToken()
        let hash = SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            if try await relay.setRejoin(group, hash: hash) { SyncKeychain.setRejoinSecret(secret, for: group) }
        } catch RelayClient.Failure.server(_, let code) where code == "PGRST202" || code == "42883" {
            rejoinUnavailable = true
        } catch {
            // Tried again after the next sync.
        }
    }

    /// After the sharing sign-in was replaced, moves every membership this phone has a
    /// secret for over to the new sign-in.
    private func rejoinIfSignInReplaced() async {
        guard let relay, await relay.takeReplacedSignIn() else { return }
        for id in states.keys { _ = await rejoin(id) }
    }

    private func rejoin(_ group: GroupID) async -> Bool {
        guard let relay, let secret = SyncKeychain.rejoinSecret(for: group) else { return false }
        return (try? await relay.rejoin(group, secret: secret)) ?? false
    }

    // MARK: Receipt photos

    private func uploadReceipts(for changes: [SyncChange], in group: GroupID, key: SymmetricKey) async throws {
        guard let relay else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ids = Set(changes.filter { $0.entity == .expense }.compactMap { try? decoder.decode(Expense.self, from: $0.body).receiptID })
        for id in ids {
            // Only the text goes up, compressed and sealed: under 1 KB instead of a 100-240 KB
            // photo (ADR 28). The photo never leaves this phone.
            guard let packed = await packedReceiptText(id), !(try await relay.hasReceipt(id)) else { continue }
            try await relay.uploadReceipt(id, ciphertext: try SyncCipher.sealReceiptText(packed, id: id, groupID: group, with: key), to: group)
        }
    }

    /// The receipt's text, read once on this phone from its photo and kept next to it.
    private func packedReceiptText(_ id: UUID) async -> Data? {
        if let packed = ReceiptPhotos.packedText(for: id) { return packed }
        guard let image = ReceiptPhotos.image(for: id),
              let lines = try? await ReceiptTextRecognizer.lines(in: [image]),
              let packed = try? ReceiptText.pack(lines) else { return nil }
        try? ReceiptPhotos.storeText(packed, for: id)
        return packed
    }

    enum ReceiptContent {
        case photo(CGImage)
        case text([String])
    }

    /// The photo when it was taken on this phone; otherwise the receipt's text, downloaded
    /// once from the relay and kept on the phone after that. Nil if it can't be found.
    func receipt(_ id: UUID, in group: GroupID) async -> ReceiptContent? {
        if let image = ReceiptPhotos.image(for: id) { return .photo(image) }
        if let packed = ReceiptPhotos.packedText(for: id), let lines = try? ReceiptText.unpack(packed) { return .text(lines) }
        guard let relay, let key = SyncKeychain.key(for: group),
              let sealed = try? await relay.downloadReceipt(id, in: group),
              let opened = try? SyncCipher.openReceipt(sealed, id: id, groupID: group, with: key) else { return nil }
        switch opened {
        case .text(let packed):
            guard let lines = try? ReceiptText.unpack(packed) else { return nil }
            try? ReceiptPhotos.storeText(packed, for: id)
            return .text(lines)
        case .photo(let jpeg):
            // Sent by an older version of the app.
            guard ReceiptPhotos.isAcceptable(jpeg) else { return nil }
            try? ReceiptPhotos.store(jpeg, for: id)
            return ReceiptPhotos.image(for: id).map(ReceiptContent.photo)
        }
    }

    /// The relay no longer has the group. Keep everything on the phone and say so.
    private func handleRemoved(_ group: GroupID) async {
        // A new sharing sign-in, not a removed group: move the membership and sync again.
        if await rejoin(group) {
            status[group] = nil
            stamps[group] = nil
            scheduleSync(group)
            return
        }
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
