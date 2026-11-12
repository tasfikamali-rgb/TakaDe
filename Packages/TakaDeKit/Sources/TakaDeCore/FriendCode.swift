import Foundation

/// A TakaDe ID (docs/adr/0021-takade-ids.md): 8 random Crockford base32 characters, 40 bits,
/// shown as `TKD-7F3K-9QXM`. Friends add each other by typing it or scanning its QR code.
/// It says nothing about the person, and it can be replaced at any time.
public struct FriendCode: Hashable, Sendable, CustomStringConvertible {
    /// Crockford base32: no I, L, O or U, so it reads aloud and types without mix-ups.
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let length = 8
    public static let prefix = "TKD"
    public static let urlHost = "friend"

    /// The 8 characters, as the server stores them.
    public let raw: String

    public init?(raw: String) {
        guard raw.count == Self.length, raw.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        self.raw = raw
    }

    /// Reads an ID however it was typed: any case, with or without "TKD", dashes or spaces.
    /// O reads as 0 and I or L as 1, as Crockford base32 allows.
    public init?(typed text: String) {
        var cleaned = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if cleaned.hasPrefix(Self.prefix), cleaned.count == Self.prefix.count + Self.length {
            cleaned.removeFirst(Self.prefix.count)
        }
        let mapped = String(cleaned.map { character -> Character in
            switch character {
            case "O": return "0"
            case "I", "L": return "1"
            default: return character
            }
        })
        self.init(raw: mapped)
    }

    /// Reads a scanned QR code: `takade://friend?c=…`, or a typed ID.
    public init?(scanned text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed), components.scheme?.lowercased() == GroupInvite.scheme {
            guard components.host?.lowercased() == Self.urlHost,
                  let value = components.queryItems?.first(where: { $0.name == "c" })?.value else { return nil }
            self.init(typed: value)
        } else {
            self.init(typed: trimmed)
        }
    }

    /// A new random ID from the given random bytes (at least 5).
    public init(randomBytes bytes: [UInt8]) {
        precondition(bytes.count >= 5)
        var bits: UInt64 = 0
        for byte in bytes.prefix(5) { bits = bits << 8 | UInt64(byte) }
        var characters: [Character] = []
        for index in (0..<Self.length).reversed() {
            characters.append(Self.alphabet[Int((bits >> (UInt64(index) * 5)) & 31)])
        }
        raw = String(characters)
    }

    /// TKD-7F3K-9QXM
    public var description: String {
        "\(Self.prefix)-\(raw.prefix(4))-\(raw.suffix(4))"
    }

    /// What the QR code holds.
    public var url: URL {
        var components = URLComponents()
        components.scheme = GroupInvite.scheme
        components.host = Self.urlHost
        components.queryItems = [.init(name: "c", value: raw)]
        return components.url!
    }
}
