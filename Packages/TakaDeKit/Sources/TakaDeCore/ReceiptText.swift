import Foundation

/// The text read from a receipt photo, as it travels to the other phones in a shared group
/// (docs/adr/0027-receipt-text-instead-of-photos.md). A photo is 100 to 240 KB on the relay;
/// its text, compressed, is usually under 1 KB, so the free database lasts far longer.
///
/// The format is small JSON (`{"v":1,"lines":[...]}`) compressed with zlib, which Android can
/// read too. Lines arrive from other phones, so they're untrusted: sizes are capped and the
/// text is shown exactly as read, never parsed into amounts.
public enum ReceiptText {
    public static let maxLines = 400
    public static let maxLineLength = 300
    /// The whole thing once decompressed.
    public static let maxBytes = 64 * 1024

    public struct Invalid: Error {}

    private struct Payload: Codable {
        var v: Int
        var lines: [String]
    }

    /// Trims each line, drops empty ones and keeps within the limits.
    public static func clean(_ lines: [String]) -> [String] {
        Array(lines.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(maxLineLength)) }
            .prefix(maxLines))
    }

    public static func encode(_ lines: [String]) throws -> Data {
        try JSONEncoder().encode(Payload(v: 1, lines: clean(lines)))
    }

    public static func decode(_ json: Data) throws -> [String] {
        guard json.count <= maxBytes, let payload = try? JSONDecoder().decode(Payload.self, from: json),
              payload.v == 1, payload.lines.count <= maxLines,
              payload.lines.allSatisfy({ $0.count <= maxLineLength })
        else { throw Invalid() }
        return payload.lines
    }
}

#if canImport(Compression)
extension ReceiptText {
    public static func pack(_ lines: [String]) throws -> Data {
        try (encode(lines) as NSData).compressed(using: .zlib) as Data
    }

    public static func unpack(_ packed: Data) throws -> [String] {
        try decode(BoundedInflate.inflate(packed, limit: maxBytes))
    }
}
#endif
