import GRDB

/// Versioned schema. Never edit a shipped migration; add a new one.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "expense_group") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("currency_code", .text).notNull()
                t.column("currency_digits", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("archived_at", .datetime)
            }
            try db.create(table: "member") { t in
                t.primaryKey("id", .text)
                t.column("group_id", .text).notNull().indexed()
                    .references("expense_group", onDelete: .cascade)
                t.column("display_name", .text).notNull()
                t.column("is_me", .boolean).notNull().defaults(to: false)
                t.column("position", .integer).notNull()
            }
            try db.create(table: "expense") { t in
                t.primaryKey("id", .text)
                t.column("group_id", .text).notNull().indexed()
                    .references("expense_group", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("total_minor", .integer).notNull()
                t.column("currency_code", .text).notNull()
                t.column("occurred_at", .datetime).notNull()
                t.column("version", .integer).notNull()
                t.column("deleted_at", .datetime)
                // Full expense (payers, split rule, allocation) as JSON. The columns above
                // exist for querying and integrity checks; this is the source of truth.
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "settlement") { t in
                t.primaryKey("id", .text)
                t.column("group_id", .text).notNull().indexed()
                    .references("expense_group", onDelete: .cascade)
                t.column("from_member", .text).notNull()
                t.column("to_member", .text).notNull()
                t.column("amount_minor", .integer).notNull().check { $0 > 0 }
                t.column("status", .text).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "audit_event") { t in
                t.primaryKey("id", .text)
                t.column("group_id", .text).notNull().indexed()
                t.column("entity", .text).notNull()
                t.column("entity_id", .text).notNull()
                t.column("action", .text).notNull()
                t.column("actor", .text)
                t.column("source", .text).notNull()
                t.column("occurred_at", .datetime).notNull()
                t.column("snapshot", .blob).notNull()
            }
            // History is append-only.
            try db.execute(sql: """
                CREATE TRIGGER audit_event_no_update BEFORE UPDATE ON audit_event
                BEGIN SELECT RAISE(ABORT, 'audit_event is append-only'); END;
                CREATE TRIGGER audit_event_no_delete BEFORE DELETE ON audit_event
                BEGIN SELECT RAISE(ABORT, 'audit_event is append-only'); END;
                """)
        }
        return migrator
    }
}
