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
        // Members' phones are untrusted: a small upload must not inflate into a huge one.
        let json = try BoundedInflate.inflate(packed, limit: SyncLimits.maxChangeBytes)
        let change = try decoder.decode(SyncChange.self, from: json)
        guard change.id == changeID, change.groupID == groupID else { throw Failure.mismatch }
        return change
    }

    // MARK: Bundles (docs/adr/0034-packed-changes-and-backups.md)

    private static let bundlePrefix = "b1."

    /// A whole group packed into one upload: compressed together, which is far smaller than
    /// the same changes sealed one by one. The group id, bundle id and the relay position it
    /// covers are bound in, so a bundle can't be moved to another group or another position.
    static func sealBundle(_ changes: [SyncChange], id: UUID, through: Int64, groupID: GroupID, with key: SymmetricKey) throws -> String {
        let json = try encoder.encode(changes)
        let packed = try (json as NSData).compressed(using: .zlib) as Data
        let box = try AES.GCM.seal(packed, using: key, authenticating: bundleContext(groupID, id, through))
        guard let combined = box.combined else { throw Failure.malformed }
        return bundlePrefix + combined.base64EncodedString()
    }

    static func openBundle(_ text: String, id: UUID, through: Int64, groupID: GroupID, with key: SymmetricKey) throws -> [SyncChange] {
        guard text.hasPrefix(bundlePrefix), let combined = Data(base64Encoded: String(text.dropFirst(bundlePrefix.count))) else {
            throw Failure.malformed
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        let packed = try AES.GCM.open(box, using: key, authenticating: bundleContext(groupID, id, through))
        let json = try BoundedInflate.inflate(packed, limit: SyncLimits.maxBundleBytes)
        let changes = try decoder.decode([SyncChange].self, from: json)
        guard changes.count <= SyncLimits.maxBundleChanges, changes.allSatisfy({ $0.groupID == groupID }) else { throw Failure.mismatch }
        return changes
    }

    private static func bundleContext(_ group: GroupID, _ id: UUID, _ through: Int64) -> Data {
        Data("takade.bundle.v1|\(group)|\(id.uuidString)|\(through)".utf8)
    }

    // MARK: Receipts

    /// What a shared receipt turned out to be. New uploads are always text (ADR 28); photos
    /// are what older versions of the app sent.
    enum Receipt {
        case photo(Data)
        case text(packed: Data)
    }

    private static let textPrefix = "t1."

    /// The receipt's text, already compressed by `ReceiptText.pack`. Sealed with its own
    /// authenticated context, so a photo can't be passed off as text or the other way round.
    static func sealReceiptText(_ packed: Data, id: UUID, groupID: GroupID, with key: SymmetricKey) throws -> String {
        let box = try AES.GCM.seal(packed, using: key, authenticating: receiptTextContext(groupID, id))
        guard let combined = box.combined else { throw Failure.malformed }
        return textPrefix + combined.base64EncodedString()
    }

    static func openReceipt(_ text: String, id: UUID, groupID: GroupID, with key: SymmetricKey) throws -> Receipt {
        if text.hasPrefix(textPrefix) {
            guard let combined = Data(base64Encoded: String(text.dropFirst(textPrefix.count))) else { throw Failure.malformed }
            let packed = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: receiptTextContext(groupID, id))
            _ = try ReceiptText.unpack(packed) // checked before it's kept
            return .text(packed: packed)
        }
        guard text.hasPrefix(prefix), let combined = Data(base64Encoded: String(text.dropFirst(prefix.count))) else { throw Failure.malformed }
        return .photo(try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: receiptContext(groupID, id)))
    }

    private static func receiptContext(_ group: GroupID, _ id: UUID) -> Data {
        Data("takade.receipt.v1|\(group)|\(id.uuidString)".utf8)
    }

    private static func receiptTextContext(_ group: GroupID, _ id: UUID) -> Data {
        Data("takade.receipt-text.v1|\(group)|\(id.uuidString)".utf8)
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
