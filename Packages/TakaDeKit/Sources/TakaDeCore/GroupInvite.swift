import Foundation

/// An invite link to a shared group (docs/adr/0018-shared-groups.md).
///
///     takade://join?g=<group id>&t=<invite token>#k=<group key>
///     https://takadeapp.com/join?g=…&t=…#k=…   (once the website exists)
///
/// The token lets the relay add the person to the group; only its hash is stored there. The
/// key decrypts the group and sits after the "#": browsers never send that part to a server,
/// and the app never sends it anywhere. Anyone holding the whole link can join until it
/// expires or is stopped, so the app says so when sharing it.
public struct GroupInvite: Equatable, Sendable {
    public static let scheme = "takade"
    /// The future website. Links on it open the app once Associated Domains is set up.
    public static let webHosts: Set<String> = ["takadeapp.com", "www.takadeapp.com"]
    public static let keyLength = 32

    public let groupID: GroupID
    public let token: String
    public let key: Data

    public init?(groupID: GroupID, token: String, key: Data) {
        guard Self.isValidToken(token), key.count == Self.keyLength else { return nil }
        self.groupID = groupID
        self.token = token
        self.key = key
    }

    /// The link to share, in the app's own scheme.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "join"
        components.queryItems = [.init(name: "g", value: groupID.description), .init(name: "t", value: token)]
        components.fragment = "k=" + key.base64URLEncoded
        return components.url!
    }

    /// Reads a tapped link. Anything else (other hosts, missing or malformed parts) is nil.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        switch scheme {
        case Self.scheme:
            guard components.host?.lowercased() == "join" else { return nil }
        case "https":
            guard let host = components.host?.lowercased(), Self.webHosts.contains(host),
                  components.path == "/join" || components.path == "/join/" else { return nil }
        default:
            return nil
        }
        let items = components.queryItems ?? []
        guard let groupText = items.first(where: { $0.name == "g" })?.value, let groupUUID = UUID(uuidString: groupText),
              let token = items.first(where: { $0.name == "t" })?.value,
              let fragment = components.fragment, fragment.hasPrefix("k="),
              let key = Data(base64URLEncoded: String(fragment.dropFirst(2)))
        else { return nil }
        self.init(groupID: GroupID(groupUUID), token: token, key: key)
    }

    /// Finds an invite inside pasted text, such as a whole WhatsApp message.
    public init?(text: String) {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "\"" })
        for word in words {
            let candidate = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)("))
            if let url = URL(string: candidate), let invite = GroupInvite(url: url) {
                self = invite
                return
            }
        }
        return nil
    }

    public static func isValidToken(_ token: String) -> Bool {
        (20...128).contains(token.count) && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

extension Data {
    /// Base64 with URL-safe characters and no padding (RFC 4648 §5).
    public var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public init?(base64URLEncoded text: String) {
        guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
