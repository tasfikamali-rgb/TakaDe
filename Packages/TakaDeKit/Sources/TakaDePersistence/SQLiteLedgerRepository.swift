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
        let shared = try encoder.encode(group.forSharing)
        try await db.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM expense_group WHERE id = ?)", arguments: [group.id.description]) ?? false
            try db.execute(sql: """
                INSERT INTO expense_group (id, name, currency_code, currency_digits, created_at, archived_at, simplify_debts, kind, manager_id, accent)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, archived_at = excluded.archived_at,
                    simplify_debts = excluded.simplify_debts, kind = excluded.kind, manager_id = excluded.manager_id, accent = excluded.accent
                """, arguments: [group.id.description, group.name, group.currency.code, group.currency.minorUnitDigits, group.createdAt, group.archivedAt,
                                 group.simplifiesDebts, group.kind.rawValue, group.managerID?.description, group.accentHex])
            // Members: upsert listed members. Nobody is deleted here; `removeMember` does that,
            // and only for someone nothing in the group mentions.
            let profileID = try String.fetchOne(db, sql: "SELECT id FROM local_profile LIMIT 1")
            for (position, member) in group.members.enumerated() {
                try db.execute(sql: """
                    INSERT INTO member (id, group_id, display_name, is_me, position, profile_id, nickname) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, is_me = excluded.is_me,
                        position = excluded.position, profile_id = excluded.profile_id, nickname = excluded.nickname
                    """, arguments: [member.id.description, group.id.description, member.displayName, member.isMe, position,
                                     member.isMe ? profileID : nil, member.nickname])
            }
            try Self.audit(db, AuditEvent(groupID: group.id, entity: .group, entityID: group.id.rawValue, action: exists ? .edited : .created, actor: actor, snapshot: snapshot))
            try Self.enqueue(db, group: group.id, entity: .group, body: shared)
        }
    }

    public func removeMember(_ member: MemberID, from group: GroupID, actor: MemberID?) async throws {
        let id = member.description
        let groupID = group.description
        let encoder = self.encoder
        try await db.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT is_me FROM member WHERE id = ? AND group_id = ?", arguments: [id, groupID]) else { return }
            if row["is_me"] as Bool { throw MemberRemovalError.isMe }
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM expense_group WHERE id = ? AND manager_id = ?)", arguments: [groupID, id]) ?? false {
                throw MemberRemovalError.isManager
            }
            // Expenses keep members inside their JSON (who paid, the split). A member id is a
            // UUID, so a text match can't hit anything else. Deleted expenses count too: they
            // can be brought back.
            let pattern = "%\(id)%"
            let mentioned = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM expense WHERE group_id = ? AND payload LIKE ?)
                    OR EXISTS(SELECT 1 FROM settlement WHERE group_id = ? AND (from_member = ? OR to_member = ?))
                    OR EXISTS(SELECT 1 FROM meal_count WHERE group_id = ? AND member_id = ?)
                """, arguments: [groupID, pattern, groupID, id, id, groupID, id]) ?? false
            if mentioned { throw MemberRemovalError.hasEntries }
            // Their saved bKash or bank numbers go with them (foreign key cascade).
            try db.execute(sql: "DELETE FROM member WHERE id = ?", arguments: [id])
            if let groupRow = try Row.fetchOne(db, sql: "SELECT * FROM expense_group WHERE id = ?", arguments: [groupID]) {
                let updated = try Self.group(from: groupRow, db: db)
                try Self.audit(db, AuditEvent(groupID: group, entity: .group, entityID: group.rawValue, action: .edited, actor: actor,
                                              snapshot: try encoder.encode(updated)))
                try Self.enqueue(db, group: group, entity: .group, body: try encoder.encode(updated.forSharing))
            }
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
        var expense = expense
        expense.changedBy = actor
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
            try Self.enqueue(db, group: expense.groupID, entity: .expense, body: payload)
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
            expense.changedBy = actor
            let payload = try encoder.encode(expense)
            try db.execute(sql: "UPDATE expense SET deleted_at = ?, version = ?, payload = ? WHERE id = ?",
                           arguments: [expense.deletedAt, expense.version, payload, id.description])
            try Self.audit(db, AuditEvent(groupID: expense.groupID, entity: .expense, entityID: id.rawValue, action: .deleted, actor: actor, snapshot: payload))
            try Self.enqueue(db, group: expense.groupID, entity: .expense, body: payload)
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
        var settlement = settlement
        settlement.changedBy = actor
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
            if let previous {
                // An edit fixes the amount, method or transaction id; who paid whom stays.
                guard previous.groupID == settlement.groupID, previous.from == settlement.from, previous.to == settlement.to else {
                    throw LedgerError.invalidPayment
                }
                if previous.amount != settlement.amount,
                   !Settlement.canChangeAmount(status: previous.status, to: previous.to, by: actor) {
                    throw LedgerError.settlementAmountLocked
                }
            }
            try db.execute(sql: """
                INSERT INTO settlement (id, group_id, from_member, to_member, amount_minor, status, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET amount_minor = excluded.amount_minor, status = excluded.status, payload = excluded.payload
                """, arguments: [settlement.id.description, settlement.groupID.description, settlement.from.description,
                                 settlement.to.description, settlement.amount.minorUnits, settlement.status.rawValue, payload])
            let action: AuditEvent.Action = previous == nil ? .created : (previous!.status != settlement.status ? .statusChanged : .edited)
            try Self.audit(db, AuditEvent(groupID: settlement.groupID, entity: .settlement, entityID: settlement.id.rawValue, action: action, actor: actor, snapshot: payload))
            try Self.enqueue(db, group: settlement.groupID, entity: .settlement, body: payload)
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

    static func audit(_ db: Database, _ event: AuditEvent) throws {
        try db.execute(sql: """
            INSERT INTO audit_event (id, group_id, entity, entity_id, action, actor, source, occurred_at, snapshot)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [event.id.uuidString, event.groupID.description, event.entity.rawValue, event.entityID.uuidString,
                             event.action.rawValue, event.actor?.description, event.source.rawValue, event.occurredAt, event.snapshot])
    }

    /// Queues a change for upload when the group is shared. Runs inside the caller's
    /// transaction, so the change and its upload record are saved together or not at all.
    static func enqueue(_ db: Database, group: GroupID, entity: SyncChange.Entity, body: Data) throws {
        let shared = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM group_sync WHERE group_id = ?)", arguments: [group.description]) ?? false
        guard shared else { return }
        try db.execute(sql: "INSERT INTO sync_outbox (change_id, group_id, entity, body, made_at) VALUES (?, ?, ?, ?, ?)",
                       arguments: [UUID().uuidString, group.description, entity.rawValue, body, Date()])
    }

    static func group(from row: Row, db: Database) throws -> ExpenseGroup {
        let id: String = row["id"]
        let members = try Row.fetchAll(db, sql: "SELECT * FROM member WHERE group_id = ? ORDER BY position", arguments: [id]).map { m in
            Member(id: MemberID(UUID(uuidString: m["id"])!), displayName: m["display_name"], isMe: m["is_me"], nickname: m["nickname"])
        }
        return ExpenseGroup(
            id: GroupID(UUID(uuidString: id)!),
            name: row["name"],
            currency: Currency(code: row["currency_code"], minorUnitDigits: row["currency_digits"]),
            members: members,
            createdAt: row["created_at"],
            archivedAt: row["archived_at"],
            simplifiesDebts: row["simplify_debts"],
            kind: GroupKind(rawValue: (row["kind"] as String?) ?? "") ?? .standard,
            managerID: (row["manager_id"] as String?).flatMap(UUID.init(uuidString:)).map(MemberID.init),
            accentHex: row["accent"]
        )
    }
}
