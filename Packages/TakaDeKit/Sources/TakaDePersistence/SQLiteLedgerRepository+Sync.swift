import Foundation
import GRDB
import TakaDeCore

/// Why a change from another phone was skipped. Skipped changes are counted, not applied.
enum SyncApplyError: Error {
    case wrongGroup
    case unknownMember
    case invalid
    case notShared
}

extension SQLiteLedgerRepository: SyncRepository {
    private static let syncEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let syncDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: State

    public func sharedGroups() async throws -> [SharedGroupState] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: Self.stateSQL + " ORDER BY s.shared_at").compactMap(Self.state(from:))
        }
    }

    public func sharedState(of group: GroupID) async throws -> SharedGroupState? {
        try await reader.read { db in
            try Row.fetchOne(db, sql: Self.stateSQL + " WHERE s.group_id = ?", arguments: [group.description]).flatMap(Self.state(from:))
        }
    }

    private static let stateSQL = """
        SELECT s.group_id, s.cursor, s.last_synced_at,
               (SELECT COUNT(*) FROM sync_outbox o WHERE o.group_id = s.group_id AND o.uploaded_at IS NULL) AS pending
        FROM group_sync s
        """

    private static func state(from row: Row) -> SharedGroupState? {
        guard let id = UUID(uuidString: row["group_id"]) else { return nil }
        return SharedGroupState(groupID: GroupID(id), cursor: row["cursor"], pendingUploads: row["pending"], lastSyncedAt: row["last_synced_at"])
    }

    // MARK: Start and stop

    public func startSharing(_ group: GroupID) async throws {
        let encoder = Self.syncEncoder
        try await writer.write { db in
            let already = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM group_sync WHERE group_id = ?)", arguments: [group.description]) ?? false
            guard !already else { return }
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM expense_group WHERE id = ?", arguments: [group.description]) else {
                throw SyncApplyError.wrongGroup
            }
            try db.execute(sql: "INSERT INTO group_sync (group_id, cursor, shared_at) VALUES (?, 0, ?)", arguments: [group.description, Date()])
            // Everything that exists so far goes up first, in an order that always makes sense
            // to the phone receiving it: the group and its people, then what refers to them.
            let snapshot = try Self.group(from: row, db: db)
            try Self.enqueue(db, group: group, entity: .group, body: encoder.encode(snapshot.forSharing))
            for body in try Data.fetchAll(db, sql: "SELECT payload FROM expense WHERE group_id = ? ORDER BY occurred_at", arguments: [group.description]) {
                try Self.enqueue(db, group: group, entity: .expense, body: body)
            }
            for body in try Data.fetchAll(db, sql: "SELECT payload FROM settlement WHERE group_id = ? ORDER BY rowid", arguments: [group.description]) {
                try Self.enqueue(db, group: group, entity: .settlement, body: body)
            }
            let meals = try Row.fetchAll(db, sql: "SELECT member_id, day, half_meals FROM meal_count WHERE group_id = ? ORDER BY day", arguments: [group.description])
            for meal in meals {
                guard let member = UUID(uuidString: meal["member_id"]), let day = MealDay(meal["day"] as String),
                      let count = try? MealCount(memberID: MemberID(member), day: day, halfMeals: meal["half_meals"]) else { continue }
                try Self.enqueue(db, group: group, entity: .meal, body: encoder.encode(count))
            }
        }
    }

    public func prepareToJoin(_ group: GroupID) async throws {
        try await writer.write { db in
            try db.execute(sql: "INSERT INTO group_sync (group_id, cursor, shared_at) VALUES (?, 0, ?) ON CONFLICT(group_id) DO NOTHING",
                           arguments: [group.description, Date()])
        }
    }

    public func stopSharing(_ group: GroupID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM sync_outbox WHERE group_id = ?", arguments: [group.description])
            try db.execute(sql: "DELETE FROM group_sync WHERE group_id = ?", arguments: [group.description])
        }
    }

    // MARK: Upload

    public func pendingChanges(in group: GroupID, limit: Int) async throws -> [SyncChange] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sync_outbox WHERE group_id = ? AND uploaded_at IS NULL ORDER BY rowid LIMIT ?", arguments: [group.description, limit])
                .compactMap { row in
                    guard let id = UUID(uuidString: row["change_id"]), let entity = SyncChange.Entity(rawValue: row["entity"]) else { return nil }
                    return SyncChange(id: id, groupID: group, entity: entity, body: row["body"], madeAt: row["made_at"])
                }
        }
    }

    public func markUploaded(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let now = Date()
        try await writer.write { db in
            for id in ids {
                try db.execute(sql: "UPDATE sync_outbox SET uploaded_at = ? WHERE change_id = ?", arguments: [now, id.uuidString])
            }
        }
    }

    public func markSynced(_ group: GroupID, at date: Date) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE group_sync SET last_synced_at = ? WHERE group_id = ?", arguments: [date, group.description])
        }
    }

    public func setMe(_ member: MemberID, in group: GroupID) async throws {
        try await writer.write { db in
            let profileID = try String.fetchOne(db, sql: "SELECT id FROM local_profile LIMIT 1")
            try db.execute(sql: "UPDATE member SET is_me = 0, profile_id = NULL WHERE group_id = ?", arguments: [group.description])
            try db.execute(sql: "UPDATE member SET is_me = 1, profile_id = ? WHERE group_id = ? AND id = ?",
                           arguments: [profileID, group.description, member.description])
        }
    }

    // MARK: Download

    public func apply(_ changes: [ReceivedChange], through lastSequence: Int64?, in group: GroupID, syncedAt: Date) async throws -> ApplyResult {
        try await writer.write { db in
            guard var cursor = try Int64.fetchOne(db, sql: "SELECT cursor FROM group_sync WHERE group_id = ?", arguments: [group.description]) else {
                throw SyncApplyError.notShared
            }
            var result = ApplyResult()
            for item in changes.sorted(by: { $0.sequence < $1.sequence }) where item.sequence > cursor {
                do {
                    // This phone's own change, back from the relay. It's applied again so every
                    // phone ends up with the same result in the same order, but not logged twice.
                    let own = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sync_outbox WHERE change_id = ?)",
                                                arguments: [item.change.id.uuidString]) ?? false
                    // Each change in its own savepoint: a rejected one leaves no partial writes.
                    try db.inSavepoint {
                        try Self.applyOne(item.change, in: group, logs: !own, db: db)
                        return .commit
                    }
                    if own {
                        try db.execute(sql: "DELETE FROM sync_outbox WHERE change_id = ?", arguments: [item.change.id.uuidString])
                    }
                    result.applied += 1
                } catch {
                    result.rejected += 1
                }
                cursor = item.sequence
            }
            // Changes that couldn't be read at all are passed as a sequence to skip past.
            if let lastSequence, lastSequence > cursor { cursor = lastSequence }
            try db.execute(sql: "UPDATE group_sync SET cursor = ?, last_synced_at = ? WHERE group_id = ?",
                           arguments: [cursor, syncedAt, group.description])
            return result
        }
    }

    private static func applyOne(_ change: SyncChange, in group: GroupID, logs: Bool, db: Database) throws {
        guard change.groupID == group else { throw SyncApplyError.wrongGroup }
        switch change.entity {
        case .group: try applyGroup(change.body, in: group, logs: logs, db: db)
        case .expense: try applyExpense(change.body, in: group, logs: logs, db: db)
        case .settlement: try applySettlement(change.body, in: group, logs: logs, db: db)
        case .meal: try applyMeal(change.body, in: group, logs: logs, db: db)
        }
    }

    private static func memberIDs(in group: GroupID, db: Database) throws -> Set<MemberID> {
        Set(try String.fetchAll(db, sql: "SELECT id FROM member WHERE group_id = ?", arguments: [group.description])
            .compactMap(UUID.init(uuidString:)).map(MemberID.init))
    }

    private static func syncAudit(_ db: Database, group: GroupID, entity: AuditEvent.Entity, id: UUID, action: AuditEvent.Action, body: Data) throws {
        try audit(db, AuditEvent(groupID: group, entity: entity, entityID: id, action: action, actor: nil, source: .sync, snapshot: body))
    }

    /// The group's settings come from the other phone. People are merged, never removed, and
    /// "which one is me" stays as this phone set it.
    private static func applyGroup(_ body: Data, in group: GroupID, logs: Bool, db: Database) throws {
        let remote = try syncDecoder.decode(ExpenseGroup.self, from: body)
        guard remote.id == group,
              !remote.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !remote.members.isEmpty,
              (0...4).contains(remote.currency.minorUnitDigits), remote.currency.code.count == 3
        else { throw SyncApplyError.invalid }
        let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM expense_group WHERE id = ?)", arguments: [group.description]) ?? false
        // Currency and creation date are fixed once the group exists.
        try db.execute(sql: """
            INSERT INTO expense_group (id, name, currency_code, currency_digits, created_at, archived_at, simplify_debts, kind, manager_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, archived_at = excluded.archived_at,
                simplify_debts = excluded.simplify_debts, kind = excluded.kind, manager_id = excluded.manager_id
            """, arguments: [group.description, remote.name, remote.currency.code, remote.currency.minorUnitDigits, remote.createdAt,
                             remote.archivedAt, remote.simplifiesDebts, remote.kind.rawValue, remote.managerID?.description])
        let remoteIDs = Set(remote.members.map(\.id))
        for (position, member) in remote.members.enumerated() {
            // A member id that belongs to another group is never moved; the update is skipped.
            try db.execute(sql: """
                INSERT INTO member (id, group_id, display_name, is_me, position) VALUES (?, ?, ?, 0, ?)
                ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, position = excluded.position
                    WHERE member.group_id = excluded.group_id
                """, arguments: [member.id.description, group.description, member.displayName, position])
        }
        // People added here and not yet seen by the other phone stay, after the others.
        let localOnly = try String.fetchAll(db, sql: "SELECT id FROM member WHERE group_id = ? ORDER BY position", arguments: [group.description])
            .filter { id in UUID(uuidString: id).map { !remoteIDs.contains(MemberID($0)) } ?? false }
        for (offset, id) in localOnly.enumerated() {
            try db.execute(sql: "UPDATE member SET position = ? WHERE id = ?", arguments: [remote.members.count + offset, id])
        }
        if logs { try syncAudit(db, group: group, entity: .group, id: group.rawValue, action: exists ? .edited : .created, body: body) }
    }

    /// The newer version of an expense wins; an older copy arriving late is ignored.
    private static func applyExpense(_ body: Data, in group: GroupID, logs: Bool, db: Database) throws {
        let expense = try syncDecoder.decode(Expense.self, from: body)
        try expense.validate()
        let currency = try String.fetchOne(db, sql: "SELECT currency_code FROM expense_group WHERE id = ?", arguments: [group.description])
        guard expense.groupID == group, expense.version >= 1, expense.total.currency.code == currency else { throw SyncApplyError.invalid }
        let members = try memberIDs(in: group, db: db)
        guard expense.paidBy.keys.allSatisfy(members.contains), expense.allocation.shares.keys.allSatisfy(members.contains) else {
            throw SyncApplyError.unknownMember
        }
        let previous = try Row.fetchOne(db, sql: "SELECT group_id, version, deleted_at FROM expense WHERE id = ?", arguments: [expense.id.description])
        if let previous {
            guard (previous["group_id"] as String) == group.description else { throw SyncApplyError.wrongGroup }
            if expense.version < (previous["version"] as Int) { return }
        }
        let wasDeleted = previous.map { ($0["deleted_at"] as Date?) != nil } ?? false
        try db.execute(sql: """
            INSERT INTO expense (id, group_id, title, total_minor, currency_code, occurred_at, version, deleted_at, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, total_minor = excluded.total_minor,
                occurred_at = excluded.occurred_at, version = excluded.version, deleted_at = excluded.deleted_at, payload = excluded.payload
            """, arguments: [expense.id.description, group.description, expense.title, expense.total.minorUnits,
                             expense.total.currency.code, expense.occurredAt, expense.version, expense.deletedAt, body])
        let action: AuditEvent.Action
        switch (previous == nil, wasDeleted, expense.deletedAt != nil) {
        case (true, _, _): action = .created
        case (false, false, true): action = .deleted
        case (false, true, false): action = .restored
        default: action = .edited
        }
        if logs { try syncAudit(db, group: group, entity: .expense, id: expense.id.rawValue, action: action, body: body) }
    }

    /// A payment from another phone follows the same rules as one made here. Above all,
    /// nothing from another phone can mark a payment confirmed: only provider evidence can.
    private static func applySettlement(_ body: Data, in group: GroupID, logs: Bool, db: Database) throws {
        let settlement = try syncDecoder.decode(Settlement.self, from: body)
        let members = try memberIDs(in: group, db: db)
        guard settlement.groupID == group, settlement.from != settlement.to, settlement.amount.minorUnits > 0,
              members.contains(settlement.from), members.contains(settlement.to)
        else { throw SyncApplyError.invalid }
        let previous = try Data.fetchOne(db, sql: "SELECT payload FROM settlement WHERE id = ?", arguments: [settlement.id.description])
            .map { try syncDecoder.decode(Settlement.self, from: $0) }
        if let previous {
            guard previous.groupID == group, previous.from == settlement.from, previous.to == settlement.to,
                  previous.amount == settlement.amount else { throw SyncApplyError.invalid }
            if previous.status != settlement.status,
               !previous.status.canTransition(to: settlement.status, withProviderEvidence: false) {
                throw LedgerError.illegalStatusTransition(from: previous.status, to: settlement.status)
            }
        } else if settlement.status == .confirmed || settlement.status == .reversed {
            throw LedgerError.illegalStatusTransition(from: .notStarted, to: settlement.status)
        }
        try db.execute(sql: """
            INSERT INTO settlement (id, group_id, from_member, to_member, amount_minor, status, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET status = excluded.status, payload = excluded.payload
            """, arguments: [settlement.id.description, group.description, settlement.from.description,
                             settlement.to.description, settlement.amount.minorUnits, settlement.status.rawValue, body])
        let action: AuditEvent.Action = previous == nil ? .created : (previous!.status != settlement.status ? .statusChanged : .edited)
        if logs { try syncAudit(db, group: group, entity: .settlement, id: settlement.id.rawValue, action: action, body: body) }
    }

    private static func applyMeal(_ body: Data, in group: GroupID, logs: Bool, db: Database) throws {
        let decoded = try syncDecoder.decode(MealCount.self, from: body)
        // Decoding skips the range check, so build it again through the checked initializer.
        guard let day = MealDay(year: decoded.day.year, month: decoded.day.month, day: decoded.day.day) else { throw SyncApplyError.invalid }
        let meal = try MealCount(memberID: decoded.memberID, day: day, halfMeals: decoded.halfMeals)
        guard try memberIDs(in: group, db: db).contains(meal.memberID) else { throw SyncApplyError.unknownMember }
        if meal.halfMeals == 0 {
            try db.execute(sql: "DELETE FROM meal_count WHERE group_id = ? AND member_id = ? AND day = ?",
                           arguments: [group.description, meal.memberID.description, meal.day.description])
        } else {
            try db.execute(sql: """
                INSERT INTO meal_count (group_id, member_id, day, half_meals, updated_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(group_id, member_id, day) DO UPDATE SET half_meals = excluded.half_meals, updated_at = excluded.updated_at
                """, arguments: [group.description, meal.memberID.description, meal.day.description, meal.halfMeals, Date()])
        }
        if logs { try syncAudit(db, group: group, entity: .meal, id: meal.memberID.rawValue, action: .edited, body: body) }
    }
}
