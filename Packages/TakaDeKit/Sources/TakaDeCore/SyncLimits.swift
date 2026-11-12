import Foundation
#if canImport(Compression)
import Compression
#endif

/// Size limits for what arrives from other phones in a shared group (docs/adr/0024-security-review.md).
///
/// Anyone holding a group's invite link can write to it, so its changes are untrusted input.
/// The limits sit far above anything the app's own screens produce: they only stop a
/// tampered phone from sending text or data big enough to freeze or crash the others.
/// Names are checked, never cut or changed.
public enum SyncLimits {
    /// One change, once decompressed. A group snapshot with hundreds of people is ~100 KB.
    public static let maxChangeBytes = 2 * 1024 * 1024
    public static let maxGroupNameLength = 200
    public static let maxPersonNameLength = 200
    public static let maxMembers = 500
    public static let maxExpenseTitleLength = 500
    public static let maxNoteLength = 5_000
    /// "#RRGGBB"
    public static let maxAccentLength = 16
    /// A receipt photo's longest side, in pixels. The app saves them at 1400.
    public static let maxReceiptPixels = 4_000

    public static func accepts(_ group: ExpenseGroup) -> Bool {
        group.name.count <= maxGroupNameLength
            && group.members.count <= maxMembers
            && group.members.allSatisfy {
                $0.displayName.count <= maxPersonNameLength && ($0.nickname?.count ?? 0) <= maxPersonNameLength
            }
            && (group.accentHex?.count ?? 0) <= maxAccentLength
    }

    public static func accepts(_ expense: Expense) -> Bool {
        expense.title.count <= maxExpenseTitleLength && (expense.note?.count ?? 0) <= maxNoteLength
    }

    public static func accepts(_ settlement: Settlement) -> Bool {
        (settlement.userReference?.count ?? 0) <= maxNoteLength
    }
}

#if canImport(Compression)
public enum BoundedInflate {
    public struct TooLarge: Error {}
    public struct Malformed: Error {}

    /// Decompresses raw DEFLATE (what `NSData.compressed(using: .zlib)` makes), refusing
    /// anything that would grow past `limit` bytes, so a tiny upload can't expand into
    /// hundreds of megabytes on the phone that opens it.
    public static func inflate(_ data: Data, limit: Int) throws -> Data {
        guard !data.isEmpty else { throw Malformed() }
        // Text usually compresses 3 to 6 times, so the first try nearly always fits.
        var capacity = min(limit + 1, max(16_384, data.count * 8))
        while true {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                              src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written > 0 else { throw Malformed() }
            if written < capacity {
                output.count = written
                return output
            }
            // The buffer filled up: either it's too big, or try again with more room.
            guard capacity <= limit else { throw TooLarge() }
            capacity = min(limit + 1, capacity * 4)
        }
    }
}
#endif
