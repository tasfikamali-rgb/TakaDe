import Foundation

/// Shared groups (docs/adr/0019-shared-groups.md). Each change to a shared group is one of
/// these, encrypted on the phone with the group's key before it goes to the relay. The relay
/// stores only ciphertext and keeps the order changes arrived in.
public struct SyncChange: Hashable, Codable, Sendable, Identifiable {
    public enum Entity: String, Codable, Sendable { case group, expense, settlement, meal }

    /// Random, and also the upload's idempotency key: sending it twice stores it once.
    public let id: UUID
    public let groupID: GroupID
    public let entity: Entity
    /// The entity as JSON, the same encoding the local database uses.
    public let body: Data
    public let madeAt: Date

    public init(id: UUID = UUID(), groupID: GroupID, entity: Entity, body: Data, madeAt: Date = Date()) {
        self.id = id
        self.groupID = groupID
        self.entity = entity
        self.body = body
        self.madeAt = madeAt
    }
}

/// A change pulled from the relay, already decrypted, with its place in the group's order.
public struct ReceivedChange: Sendable {
    public let sequence: Int64
    public let change: SyncChange

    public init(sequence: Int64, change: SyncChange) {
        self.sequence = sequence
        self.change = change
    }
}

/// A group this phone shares with other phones.
public struct SharedGroupState: Hashable, Sendable {
    public let groupID: GroupID
    /// The last relay sequence applied here.
    public let cursor: Int64
    public let pendingUploads: Int
    public let lastSyncedAt: Date?

    public init(groupID: GroupID, cursor: Int64, pendingUploads: Int, lastSyncedAt: Date?) {
        self.groupID = groupID
        self.cursor = cursor
        self.pendingUploads = pendingUploads
        self.lastSyncedAt = lastSyncedAt
    }
}

/// What happened to a batch of received changes. Rejected ones are skipped, never applied
/// halfway, so one bad change can't block the rest of the group.
public struct ApplyResult: Equatable, Sendable {
    public var applied = 0
    public var rejected = 0
    public init() {}
}

public protocol SyncRepository: Sendable {
    func sharedGroups() async throws -> [SharedGroupState]
    func sharedState(of group: GroupID) async throws -> SharedGroupState?

    /// Marks an existing group as shared and queues all of it (the group, every expense,
    /// payment and meal count, deleted ones included) for upload, in one transaction.
    func startSharing(_ group: GroupID) async throws
    /// Marks a group this phone is joining. Its data arrives through `apply`.
    func prepareToJoin(_ group: GroupID) async throws
    /// Stops syncing a group on this phone. The group and its history stay here.
    func stopSharing(_ group: GroupID) async throws

    /// Local changes not yet on the relay, oldest first.
    func pendingChanges(in group: GroupID, limit: Int) async throws -> [SyncChange]
    func markUploaded(_ ids: [UUID]) async throws

    /// Applies changes from the relay in relay order and moves the cursor, in one
    /// transaction. Nothing applied here is queued for upload again. `lastSequence` moves the
    /// cursor past changes that couldn't be decrypted, so they aren't fetched forever.
    func apply(_ changes: [ReceivedChange], through lastSequence: Int64?, in group: GroupID, syncedAt: Date) async throws -> ApplyResult
    func markSynced(_ group: GroupID, at date: Date) async throws

    /// Which person in the group uses this phone. Kept on this phone only.
    func setMe(_ member: MemberID, in group: GroupID) async throws
}

extension SyncRepository {
    public func apply(_ changes: [ReceivedChange], in group: GroupID, syncedAt: Date) async throws -> ApplyResult {
        try await apply(changes, through: nil, in: group, syncedAt: syncedAt)
    }
}

extension ExpenseGroup {
    /// The copy other phones receive: "which one is me" is per phone, so nobody is marked.
    public var forSharing: ExpenseGroup {
        var copy = self
        copy.members = members.map { Member(id: $0.id, displayName: $0.displayName, isMe: false) }
        return copy
    }
}
