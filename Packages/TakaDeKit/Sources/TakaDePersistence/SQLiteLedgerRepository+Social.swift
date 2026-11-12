import Foundation
import GRDB
import TakaDeCore

extension SQLiteLedgerRepository: SocialRepository {
    public func friends(account: String) async throws -> [Friend] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM friend WHERE account_id = ?
                ORDER BY COALESCE(last_message_at, added_at) DESC
                """, arguments: [account]).compactMap(Self.friend(from:))
        }
    }

    /// Every friend on this phone, whichever account added them. For export only.
    func allFriends() async throws -> [Friend] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM friend ORDER BY added_at").compactMap(Self.friend(from:))
        }
    }

    public func friend(id: UUID) async throws -> Friend? {
        try await reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM friend WHERE id = ?", arguments: [id.uuidString]).flatMap(Self.friend(from:))
        }
    }

    public func friend(account: String, code: FriendCode) async throws -> Friend? {
        try await reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM friend WHERE account_id = ? AND code = ?", arguments: [account, code.raw])
                .flatMap(Self.friend(from:))
        }
    }

    public func friend(account: String, publicKey: String) async throws -> Friend? {
        try await reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM friend WHERE account_id = ? AND public_key = ?", arguments: [account, publicKey])
                .flatMap(Self.friend(from:))
        }
    }

    public func save(_ friend: Friend) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                INSERT INTO friend (id, account_id, code, public_key, name, status, added_at, last_message_at,
                                    last_message_preview, unread)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET code = excluded.code, public_key = excluded.public_key,
                    name = excluded.name, status = excluded.status, last_message_at = excluded.last_message_at,
                    last_message_preview = excluded.last_message_preview, unread = excluded.unread
                """, arguments: [friend.id.uuidString, friend.accountID, friend.code.raw, friend.publicKey, friend.name,
                                 friend.status.rawValue, friend.addedAt, friend.lastMessageAt, friend.lastMessagePreview,
                                 friend.unread])
        }
    }

    public func deleteFriend(_ id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM friend_message WHERE friend_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM friend WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func messages(with friend: UUID) async throws -> [FriendMessage] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM friend_message WHERE friend_id = ? ORDER BY at, rowid",
                             arguments: [friend.uuidString]).compactMap(Self.message(from:))
        }
    }

    @discardableResult
    public func save(_ message: FriendMessage) async throws -> Bool {
        try await writer.write { db in
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM friend_message WHERE id = ?)",
                                           arguments: [message.id.uuidString]) ?? false
            if exists {
                try db.execute(sql: "UPDATE friend_message SET state = ? WHERE id = ?",
                               arguments: [message.state.rawValue, message.id.uuidString])
                return false
            }
            try db.execute(sql: """
                INSERT INTO friend_message (id, friend_id, direction, body, at, state) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [message.id.uuidString, message.friendID.uuidString, message.direction.rawValue,
                                 message.text, message.at, message.state.rawValue])
            let unread = message.direction == .incoming ? 1 : 0
            try db.execute(sql: """
                UPDATE friend SET last_message_at = MAX(COALESCE(last_message_at, ?), ?),
                    last_message_preview = CASE WHEN last_message_at IS NULL OR last_message_at <= ? THEN ? ELSE last_message_preview END,
                    unread = unread + ?
                WHERE id = ?
                """, arguments: [message.at, message.at, message.at, String(message.text.prefix(120)), unread,
                                 message.friendID.uuidString])
            return true
        }
    }

    public func markRead(_ friend: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE friend SET unread = 0 WHERE id = ?", arguments: [friend.uuidString])
        }
    }

    private static func friend(from row: Row) -> Friend? {
        guard let id = UUID(uuidString: row["id"]), let code = FriendCode(raw: row["code"]),
              let status = Friend.Status(rawValue: row["status"]) else { return nil }
        return Friend(id: id, accountID: row["account_id"], code: code, publicKey: row["public_key"], name: row["name"],
                      status: status, addedAt: row["added_at"], lastMessageAt: row["last_message_at"],
                      lastMessagePreview: row["last_message_preview"], unread: row["unread"])
    }

    private static func message(from row: Row) -> FriendMessage? {
        guard let id = UUID(uuidString: row["id"]), let friend = UUID(uuidString: row["friend_id"]),
              let direction = FriendMessage.Direction(rawValue: row["direction"]),
              let state = FriendMessage.State(rawValue: row["state"]) else { return nil }
        return FriendMessage(id: id, friendID: friend, direction: direction, text: row["body"], at: row["at"], state: state)
    }
}
