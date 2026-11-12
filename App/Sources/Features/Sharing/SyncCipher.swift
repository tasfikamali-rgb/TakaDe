import CryptoKit
import Foundation
import TakaDeCore

/// Seals each change with the group's key before upload: compressed JSON, then AES-GCM
/// (Apple CryptoKit, 256-bit key, random nonce). The group id and change id are bound in as
/// authenticated data, so a change can't be replayed into another group or under another id.
/// No custom cryptography.
enum SyncCipher {
    enum Failure: Error { case malformed, mismatch }

    private static let prefix = "v1."

    static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func seal(_ change: SyncChange, with key: SymmetricKey) throws -> String {
        let json = try encoder.encode(change)
        let packed = try (json as NSData).compressed(using: .zlib) as Data
        let box = try AES.GCM.seal(packed, using: key, authenticating: context(change.groupID, change.id))
        guard let combined = box.combined else { throw Failure.malformed }
        return prefix + combined.base64EncodedString()
    }

    static func open(_ text: String, changeID: UUID, groupID: GroupID, with key: SymmetricKey) throws -> SyncChange {
        guard text.hasPrefix(prefix), let combined = Data(base64Encoded: String(text.dropFirst(prefix.count))) else { throw Failure.malformed }
        let box = try AES.GCM.SealedBox(combined: combined)
        let packed = try AES.GCM.open(box, using: key, authenticating: context(groupID, changeID))
        let json = try (packed as NSData).decompressed(using: .zlib) as Data
        let change = try decoder.decode(SyncChange.self, from: json)
        guard change.id == changeID, change.groupID == groupID else { throw Failure.mismatch }
        return change
    }

    /// Receipt photos are already JPEG, so they're sealed without compressing again.
    static func sealReceipt(_ jpeg: Data, id: UUID, groupID: GroupID, with key: SymmetricKey) throws -> String {
        let box = try AES.GCM.seal(jpeg, using: key, authenticating: receiptContext(groupID, id))
        guard let combined = box.combined else { throw Failure.malformed }
        return prefix + combined.base64EncodedString()
    }

    static func openReceipt(_ text: String, id: UUID, groupID: GroupID, with key: SymmetricKey) throws -> Data {
        guard text.hasPrefix(prefix), let combined = Data(base64Encoded: String(text.dropFirst(prefix.count))) else { throw Failure.malformed }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: receiptContext(groupID, id))
    }

    private static func receiptContext(_ group: GroupID, _ id: UUID) -> Data {
        Data("takade.receipt.v1|\(group)|\(id.uuidString)".utf8)
    }

    private static func context(_ group: GroupID, _ change: UUID) -> Data {
        Data("takade.sync.v1|\(group)|\(change.uuidString)".utf8)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
