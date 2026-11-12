import Foundation
import GRDB
import TakaDeCore

extension SQLiteLedgerRepository: ProfileRepository {
    public func profile() async throws -> LocalProfile? {
        try await reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM local_profile LIMIT 1").map(Self.profile(from:))
        }
    }

    public func save(_ profile: LocalProfile) async throws {
        // The on-device link predates accounts and only ever holds Apple or Google.
        let onDevice = profile.account.flatMap { [.apple, .google].contains($0.provider) ? $0 : nil }
        try await writer.write { db in
            // One row only: the person using this device.
            try db.execute(sql: "DELETE FROM local_profile WHERE id != ?", arguments: [profile.id.uuidString])
            try db.execute(sql: """
                INSERT INTO local_profile (id, display_name, locale, digit_style, provider, provider_user_id, email,
                                           account_id, account_email, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, locale = excluded.locale,
                    digit_style = excluded.digit_style, provider = excluded.provider,
                    provider_user_id = excluded.provider_user_id, email = excluded.email,
                    account_id = excluded.account_id, account_email = excluded.account_email
                """, arguments: [profile.id.uuidString, profile.displayName, profile.languageCode, profile.digitStyle,
                                 onDevice?.provider.rawValue, onDevice?.providerUserID, onDevice?.email,
                                 profile.accountID, profile.accountEmail, profile.createdAt])
            try db.execute(sql: "UPDATE member SET profile_id = ? WHERE is_me = 1", arguments: [profile.id.uuidString])
        }
    }

    public func accountIdentities() async throws -> [AccountIdentity] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM account_identity ORDER BY linked_at").compactMap { row in
                guard let provider = SignInProvider(rawValue: row["provider"]) else { return nil }
                return AccountIdentity(id: row["id"], provider: provider, providerUserID: row["provider_user_id"],
                                       email: row["email"], linkedAt: row["linked_at"])
            }
        }
    }

    public func replaceAccountIdentities(_ identities: [AccountIdentity]) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM account_identity")
            for identity in identities {
                try db.execute(sql: """
                    INSERT INTO account_identity (id, provider, provider_user_id, email, linked_at) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(provider, provider_user_id) DO UPDATE SET id = excluded.id, email = excluded.email,
                        linked_at = excluded.linked_at
                    """, arguments: [identity.id, identity.provider.rawValue, identity.providerUserID, identity.email, identity.linkedAt])
            }
        }
    }

    public func paymentHandles(for member: MemberID) async throws -> [PaymentHandle] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM payment_handle WHERE member_id = ? ORDER BY created_at", arguments: [member.description])
                .compactMap(Self.handle(from:))
        }
    }

    public func save(_ handle: PaymentHandle) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                INSERT INTO payment_handle (id, member_id, rail, handle, label, created_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET rail = excluded.rail, handle = excluded.handle, label = excluded.label
                """, arguments: [handle.id.uuidString, handle.memberID.description, handle.rail.rawValue, handle.handle,
                                 handle.label, handle.createdAt])
        }
    }

    public func deletePaymentHandle(_ id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM payment_handle WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func export() async throws -> LedgerExport {
        let profile = try await profile()
        var groups: [LedgerExport.GroupData] = []
        for group in try await self.groups() {
            var handles: [PaymentHandle] = []
            for member in group.members { handles += try await paymentHandles(for: member.id) }
            groups.append(LedgerExport.GroupData(group: group,
                                expenses: try await expenses(in: group.id, includeDeleted: true),
                                settlements: try await settlements(in: group.id),
                                history: try await history(of: group.id),
                                paymentHandles: handles))
        }
        var friends: [LedgerExport.FriendData] = []
        for friend in try await allFriends() {
            friends.append(LedgerExport.FriendData(friend: friend, messages: try await messages(with: friend.id)))
        }
        return LedgerExport(profile: profile, accountIdentities: try await accountIdentities(), groups: groups, friends: friends)
    }

    public func eraseEverything() async throws {
        try await writer.write { db in
            // History is append-only for normal use; erasing everything is the one exception,
            // so the guards come off and go back on inside the same transaction.
            try db.execute(sql: """
                DROP TRIGGER IF EXISTS audit_event_no_delete;
                DELETE FROM audit_event;
                DELETE FROM payment_handle;
                DELETE FROM meal_count;
                DELETE FROM settlement;
                DELETE FROM expense;
                DELETE FROM member;
                DELETE FROM expense_group;
                DELETE FROM account_identity;
                DELETE FROM friend_message;
                DELETE FROM friend;
                DELETE FROM sync_outbox;
                DELETE FROM group_sync;
                DELETE FROM local_profile;
                CREATE TRIGGER audit_event_no_delete BEFORE DELETE ON audit_event
                BEGIN SELECT RAISE(ABORT, 'audit_event is append-only'); END;
                """)
        }
        // Rewrites the file so deleted rows don't stay readable in free pages.
        try await writer.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }
    }

    private static func profile(from row: Row) -> LocalProfile {
        let provider = (row["provider"] as String?).flatMap(SignInProvider.init(rawValue:))
        let account = provider.flatMap { p in
            (row["provider_user_id"] as String?).map { LinkedAccount(provider: p, providerUserID: $0, email: row["email"]) }
        }
        return LocalProfile(id: UUID(uuidString: row["id"])!, displayName: row["display_name"], languageCode: row["locale"],
                            digitStyle: row["digit_style"], account: account, accountID: row["account_id"],
                            accountEmail: row["account_email"], createdAt: row["created_at"])
    }

    private static func handle(from row: Row) -> PaymentHandle? {
        guard let id = UUID(uuidString: row["id"]), let member = UUID(uuidString: row["member_id"]),
              let rail = PaymentHandle.Rail(rawValue: row["rail"]) else { return nil }
        return try? PaymentHandle(id: id, memberID: MemberID(member), rail: rail, handle: row["handle"],
                                  label: row["label"], createdAt: row["created_at"])
    }
}
