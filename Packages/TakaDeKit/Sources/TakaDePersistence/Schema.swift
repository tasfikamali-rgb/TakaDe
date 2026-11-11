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

        // Release 1 local profile (docs/adr/0011-on-device-sign-in.md). Still nothing leaves the device.
        migrator.registerMigration("v2_local_profile") { db in
            try db.create(table: "local_profile") { t in
                t.primaryKey("id", .text)
                t.column("display_name", .text).notNull()
                t.column("locale", .text)
                t.column("digit_style", .text)
                // The linked Apple or Google sign-in. Tokens are never stored here (Keychain).
                t.column("provider", .text).check { ["apple", "google"].contains($0) }
                t.column("provider_user_id", .text)
                t.column("email", .text)
                t.column("created_at", .datetime).notNull()
            }
            try db.alter(table: "member") { t in
                t.add(column: "profile_id", .text).references("local_profile", onDelete: .setNull)
            }
            try db.create(table: "payment_handle") { t in
                t.primaryKey("id", .text)
                t.column("member_id", .text).notNull().indexed()
                    .references("member", onDelete: .cascade)
                t.column("rail", .text).notNull()
                    .check { ["bkash", "nagad", "rocket", "upay", "bank"].contains($0) }
                t.column("handle", .text).notNull()
                t.column("label", .text)
                t.column("created_at", .datetime).notNull()
            }
        }

        // Per-group settings. Existing groups keep simplified debts on.
        migrator.registerMigration("v3_group_settings") { db in
            try db.alter(table: "expense_group") { t in
                t.add(column: "simplify_debts", .boolean).notNull().defaults(to: true)
            }
        }
        return migrator
    }
}
