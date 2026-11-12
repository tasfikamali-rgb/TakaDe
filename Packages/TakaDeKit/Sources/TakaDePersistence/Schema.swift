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

        // Mess groups: a manager and daily meal counts (docs/adr/0015-mess-mode.md).
        migrator.registerMigration("v4_mess") { db in
            try db.alter(table: "expense_group") { t in
                t.add(column: "kind", .text).notNull().defaults(to: "standard")
                t.add(column: "manager_id", .text)
            }
            try db.create(table: "meal_count") { t in
                t.column("group_id", .text).notNull().references("expense_group", onDelete: .cascade)
                t.column("member_id", .text).notNull().references("member", onDelete: .cascade)
                t.column("day", .text).notNull()            // "2026-11-05", no time zone
                t.column("half_meals", .integer).notNull().check { $0 >= 0 && $0 <= 40 }
                t.column("updated_at", .datetime).notNull()
                t.primaryKey(["group_id", "member_id", "day"])
            }
        }
        // TakaDe accounts on the sign-in service (docs/adr/0016-accounts-on-supabase.md). The
        // phone keeps the account id, its email and which sign-ins are linked; tokens stay
        // in the Keychain. The old provider check allowed only Apple and Google, so the
        // linked-on-device columns are left as they are and new providers live in
        // account_identity.
        migrator.registerMigration("v5_account_identity") { db in
            try db.alter(table: "local_profile") { t in
                t.add(column: "account_id", .text)
                t.add(column: "account_email", .text)
            }
            try db.create(table: "account_identity") { t in
                t.primaryKey("id", .text)
                t.column("provider", .text).notNull()
                    .check { ["apple", "google", "microsoft", "email"].contains($0) }
                t.column("provider_user_id", .text).notNull()
                t.column("email", .text)
                t.column("linked_at", .datetime).notNull()
                t.uniqueKey(["provider", "provider_user_id"])
            }
        }
        // Shared groups (docs/adr/0019-shared-groups.md). Changes to a shared group are
        // queued in sync_outbox in the same transaction as the change itself, so nothing is
        // lost if the app quits before uploading. Group keys are in the Keychain, never here.
        migrator.registerMigration("v6_group_sync") { db in
            try db.create(table: "group_sync") { t in
                // No foreign key: a group being joined has no row in expense_group yet.
                t.primaryKey("group_id", .text)
                t.column("cursor", .integer).notNull().defaults(to: 0)
                t.column("shared_at", .datetime).notNull()
                t.column("last_synced_at", .datetime)
            }
            try db.create(table: "sync_outbox") { t in
                t.primaryKey("change_id", .text)
                t.column("group_id", .text).notNull().indexed()
                t.column("entity", .text).notNull()
                t.column("body", .blob).notNull()
                t.column("made_at", .datetime).notNull()
                // Set once the relay has it. The row stays until the change comes back from
                // the relay, so this phone knows it's its own and doesn't log it twice.
                t.column("uploaded_at", .datetime)
            }
        }
        // Per-group nicknames (Sabit, 2026-11-12). The name itself stays as entered; a
        // nickname is only what this group calls someone.
        migrator.registerMigration("v7_member_nickname") { db in
            try db.alter(table: "member") { t in
                t.add(column: "nickname", .text)
            }
        }
        // The group's colour, from its photo (Sabit, 2026-11-12). The photo itself is a file
        // on the phone, not in the database.
        migrator.registerMigration("v8_group_accent") { db in
            try db.alter(table: "expense_group") { t in
                t.add(column: "accent", .text)
            }
        }
        // The Social tab (docs/adr/0024-friend-messages.md): friends added by TakaDe ID and
        // the messages with them. Kept on this phone; the server only passes sealed messages
        // along. Each friend belongs to the account signed in when they were added.
        migrator.registerMigration("v9_social") { db in
            try db.create(table: "friend") { t in
                t.primaryKey("id", .text)
                t.column("account_id", .text).notNull()
                t.column("code", .text).notNull()
                t.column("public_key", .text).notNull()
                t.column("name", .text).notNull()
                t.column("status", .text).notNull()
                    .check { ["friend", "request", "blocked"].contains($0) }
                t.column("added_at", .datetime).notNull()
                t.column("last_message_at", .datetime)
                t.column("last_message_preview", .text)
                t.column("unread", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["account_id", "code"])
            }
            try db.create(table: "friend_message") { t in
                t.primaryKey("id", .text)
                t.column("friend_id", .text).notNull().indexed()
                    .references("friend", onDelete: .cascade)
                t.column("direction", .text).notNull()
                    .check { ["outgoing", "incoming", "notice"].contains($0) }
                t.column("body", .text).notNull()
                t.column("at", .datetime).notNull()
                t.column("state", .text).notNull()
                    .check { ["sending", "sent", "failed", "received"].contains($0) }
            }
        }
        return migrator
    }
}
