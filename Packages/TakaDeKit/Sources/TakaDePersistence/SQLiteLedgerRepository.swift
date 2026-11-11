import Foundation
import GRDB
import TakaDeCore

/// Local SQLite storage. The database file is NOT encrypted by this class; it relies on
/// iOS Data Protection (see docs/adr/0003-grdb-for-local-sqlite.md).
public final class SQLiteLedgerRepository: LedgerRepository, @unchecked Sendable {
    private let db: DatabaseQueue
    var reader: DatabaseQueue { db }
    var writer: DatabaseQueue { db }
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Opens (or creates) the database at `path` and runs pending migrations.
    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(path: path, configuration: config)
        try Schema.migrator.migrate(db)
    }

    /// An in-memory database, for tests and previews.
    public init() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(configuration: config)
        try Schema.migrator.migrate(db)
    }

    // MARK: Groups

    public func groups() async throws -> [ExpenseGroup] {
        try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM expense_group ORDER BY created_at DESC")
            return try rows.map { try Self.group(from: $0, db: db) }
        }
    }

    public func group(_ id: GroupID) async throws -> ExpenseGroup? {
        try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM expense_group WHERE id = ?", arguments: [id.description]) else { return nil }
            return try Self.group(from: row, db: db)
        }
    }

    public func save(_ group: ExpenseGroup, actor: MemberID?) async throws {
        let snapshot = try encoder.encode(group)
        try await db.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM expense_group WHERE id = ?)", arguments: [group.id.description]) ?? false
            try db.execute(sql: """
                INSERT INTO expense_group (id, name, currency_code, currency_digits, created_at, archived_at, simplify_debts)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, archived_at = excluded.archived_at,
                    simplify_debts = excluded.simplify_debts
                """, arguments: [group.id.description, group.name, group.currency.code, group.currency.minorUnitDigits, group.createdAt, group.archivedAt,
                                 group.simplifiesDebts])
            // Members: upsert listed members. Removing a member who has entries is not allowed
            // in v1, so members are never deleted here.
            let profileID = try String.fetchOne(db, sql: "SELECT id FROM local_profile LIMIT 1")
            for (position, member) in group.members.enumerated() {
                try db.execute(sql: """
                    INSERT INTO member (id, group_id, display_name, is_me, position, profile_id) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, is_me = excluded.is_me,
                        position = excluded.position, profile_id = excluded.profile_id
                    """, arguments: [member.id.description, group.id.description, member.displayName, member.isMe, position,
                                     member.isMe ? profileID : nil])
            }
            try Self.audit(db, AuditEvent(groupID: group.id, entity: .group, entityID: group.id.rawValue, action: exists ? .edited : .created, actor: actor, snapshot: snapshot))
        }
    }

    // MARK: Expenses

    public func expenses(in group: GroupID, includeDeleted: Bool) async throws -> [Expense] {
        let decoder = self.decoder
        return try await db.read { db in
            let sql = includeDeleted
                ? "SELECT payload FROM expense WHERE group_id = ? ORDER BY occurred_at DESC"
                : "SELECT payload FROM expense WHERE group_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC"
            return try Data.fetchAll(db, sql: sql, arguments: [group.description]).map { try decoder.decode(Expense.self, from: $0) }
        }
    }

    public func save(_ expense: Expense, actor: MemberID?) async throws {
        try expense.validate()
        let payload = try encoder.encode(expense)
        try await db.write { db in
            let existingVersion = try Int.fetchOne(db, sql: "SELECT version FROM expense WHERE id = ?", arguments: [expense.id.description])
            try db.execute(sql: """
                INSERT INTO expense (id, group_id, title, total_minor, currency_code, occurred_at, version, deleted_at, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET title = excluded.title, total_minor = excluded.total_minor,
                    occurred_at = excluded.occurred_at, version = excluded.version, deleted_at = excluded.deleted_at, payload = excluded.payload
                """, arguments: [expense.id.description, expense.groupID.description, expense.title, expense.total.minorUnits,
                                 expense.total.currency.code, expense.occurredAt, expense.version, expense.deletedAt, payload])
            try Self.audit(db, AuditEvent(groupID: expense.groupID, entity: .expense, entityID: expense.id.rawValue,
                                          action: existingVersion == nil ? .created : .edited, actor: actor, snapshot: payload))
        }
    }

    public func delete(_ id: ExpenseID, actor: MemberID?) async throws {
        let decoder = self.decoder, encoder = self.encoder
        try await db.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM expense WHERE id = ?", arguments: [id.description]) else { return }
            var expense = try decoder.decode(Expense.self, from: data)
            guard expense.deletedAt == nil else { return }
            expense.deletedAt = Date()
            expense.version += 1
            let payload = try encoder.encode(expense)
            try db.execute(sql: "UPDATE expense SET deleted_at = ?, version = ?, payload = ? WHERE id = ?",
                           arguments: [expense.deletedAt, expense.version, payload, id.description])
            try Self.audit(db, AuditEvent(groupID: expense.groupID, entity: .expense, entityID: id.rawValue, action: .deleted, actor: actor, snapshot: payload))
        }
    }

    // MARK: Settlements

    public func settlements(in group: GroupID) async throws -> [Settlement] {
        let decoder = self.decoder
        return try await db.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM settlement WHERE group_id = ?", arguments: [group.description])
                .map { try decoder.decode(Settlement.self, from: $0) }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func save(_ settlement: Settlement, actor: MemberID?) async throws {
        let payload = try encoder.encode(settlement)
        let decoder = self.decoder
        try await db.write { db in
            let previous = try Data.fetchOne(db, sql: "SELECT payload FROM settlement WHERE id = ?", arguments: [settlement.id.description])
                .map { try decoder.decode(Settlement.self, from: $0) }
            if previous == nil && settlement.status == .confirmed {
                throw LedgerError.illegalStatusTransition(from: .notStarted, to: .confirmed)
            }
            if let previous, previous.status != settlement.status,
               !previous.status.canTransition(to: settlement.status, withProviderEvidence: false) {
                // No provider evidence path exists in this storage layer.
                throw LedgerError.illegalStatusTransition(from: previous.status, to: settlement.status)
            }
            try db.execute(sql: """
                INSERT INTO settlement (id, group_id, from_member, to_member, amount_minor, status, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET status = excluded.status, payload = excluded.payload
                """, arguments: [settlement.id.description, settlement.groupID.description, settlement.from.description,
                                 settlement.to.description, settlement.amount.minorUnits, settlement.status.rawValue, payload])
            let action: AuditEvent.Action = previous == nil ? .created : (previous!.status != settlement.status ? .statusChanged : .edited)
            try Self.audit(db, AuditEvent(groupID: settlement.groupID, entity: .settlement, entityID: settlement.id.rawValue, action: action, actor: actor, snapshot: payload))
        }
    }

    // MARK: History

    public func history(of group: GroupID) async throws -> [AuditEvent] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM audit_event WHERE group_id = ? ORDER BY occurred_at DESC", arguments: [group.description]).map { row in
                AuditEvent(
                    id: UUID(uuidString: row["id"])!,
                    groupID: GroupID(UUID(uuidString: row["group_id"])!),
                    entity: AuditEvent.Entity(rawValue: row["entity"])!,
                    entityID: UUID(uuidString: row["entity_id"])!,
                    action: AuditEvent.Action(rawValue: row["action"])!,
                    actor: (row["actor"] as String?).flatMap(UUID.init(uuidString:)).map(MemberID.init),
                    source: AuditEvent.Source(rawValue: row["source"])!,
                    occurredAt: row["occurred_at"],
                    snapshot: row["snapshot"]
                )
            }
        }
    }

    // MARK: Helpers

    private static func audit(_ db: Database, _ event: AuditEvent) throws {
        try db.execute(sql: """
            INSERT INTO audit_event (id, group_id, entity, entity_id, action, actor, source, occurred_at, snapshot)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [event.id.uuidString, event.groupID.description, event.entity.rawValue, event.entityID.uuidString,
                             event.action.rawValue, event.actor?.description, event.source.rawValue, event.occurredAt, event.snapshot])
    }

    private static func group(from row: Row, db: Database) throws -> ExpenseGroup {
        let id: String = row["id"]
        let members = try Row.fetchAll(db, sql: "SELECT * FROM member WHERE group_id = ? ORDER BY position", arguments: [id]).map { m in
            Member(id: MemberID(UUID(uuidString: m["id"])!), displayName: m["display_name"], isMe: m["is_me"])
        }
        return ExpenseGroup(
            id: GroupID(UUID(uuidString: id)!),
            name: row["name"],
            currency: Currency(code: row["currency_code"], minorUnitDigits: row["currency_digits"]),
            members: members,
            createdAt: row["created_at"],
            archivedAt: row["archived_at"],
            simplifiesDebts: row["simplify_debts"]
        )
    }
}
