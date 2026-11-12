import Foundation
import ImageIO
import TakaDeCore
import UIKit
import UniformTypeIdentifiers

/// Friends' profile photos, as their own phones sent them over the encrypted channel. Small
/// JPEGs in the protected Ledger folder, one per friend; never uploaded anywhere.
enum FriendPhotos {
    /// The side of the square photo sent to friends.
    static let side: CGFloat = 128
    private static var cache: [UUID: UIImage] = [:]

    private static var folder: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Ledger/FriendPhotos", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }

    private static func url(for id: UUID) -> URL? { folder?.appendingPathComponent(id.uuidString + ".jpg") }

    static func image(for id: UUID) -> UIImage? {
        if let cached = cache[id] { return cached }
        guard let url = url(for: id), let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache[id] = image
        return image
    }

    /// Keeps a photo from a friend if it's one small square-ish JPEG; anything else is ignored.
    static func store(base64 text: String, for id: UUID) {
        guard let data = Data(base64Encoded: text), isAcceptable(data), let url = url(for: id) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cache[id] = UIImage(data: data)
    }

    static func remove(_ id: UUID) {
        cache[id] = nil
        if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
    }

    static func removeAll() {
        cache = [:]
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    /// Anyone who knows your TakaDe ID can send a hello, so its photo is untrusted input.
    static func isAcceptable(_ data: Data) -> Bool {
        guard data.count <= FriendEnvelope.maxPhotoBytes, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return (1...512).contains(width) && (1...512).contains(height)
    }

    /// Your own profile photo, shrunk for sending to a friend, as base64. Nil without one.
    static func mine() -> String? {
        guard let photo = ProfilePhotoFile.load() else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: side, height: side)
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.7, 0.5, 0.3] {
            if let jpeg = small.jpegData(compressionQuality: quality), jpeg.count <= FriendEnvelope.maxPhotoBytes {
                return jpeg.base64EncodedString()
            }
        }
        return nil
    }
}
