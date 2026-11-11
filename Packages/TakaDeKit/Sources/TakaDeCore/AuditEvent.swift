import Foundation

/// One append-only entry in a group's history. Who/when/what for every change.
public struct AuditEvent: Hashable, Codable, Sendable, Identifiable {
    public enum Entity: String, Codable, Sendable { case group, member, expense, settlement, meal }
    public enum Action: String, Codable, Sendable { case created, edited, deleted, restored, statusChanged = "status_changed" }
    /// Where the change came from. Only `.local` exists today.
    public enum Source: String, Codable, Sendable { case local }

    public let id: UUID
    public let groupID: GroupID
    public let entity: Entity
    public let entityID: UUID
    public let action: Action
    public let actor: MemberID?
    public let source: Source
    public let occurredAt: Date
    /// JSON snapshot of the entity after the change.
    public let snapshot: Data

    public init(id: UUID = UUID(), groupID: GroupID, entity: Entity, entityID: UUID, action: Action, actor: MemberID?, source: Source = .local, occurredAt: Date = Date(), snapshot: Data) {
        self.id = id
        self.groupID = groupID
        self.entity = entity
        self.entityID = entityID
        self.action = action
        self.actor = actor
        self.source = source
        self.occurredAt = occurredAt
        self.snapshot = snapshot
    }
}
