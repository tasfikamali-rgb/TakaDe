import CoreGraphics
import Foundation
import ImageIO
import TakaDeCore
import UniformTypeIdentifiers

/// Receipt photos on this phone: small grayscale JPEGs in the protected Ledger folder,
/// one file per receipt, named by its id. Never in the photo library, never in SQLite.
enum ReceiptPhotos {
    /// Big enough to read every line of a receipt, small enough for the free plan:
    /// usually 60 to 150 KB.
    static let longEdge: CGFloat = 1400
    static let maxBytes = 180_000

    static var folder: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Ledger/Receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }

    static func url(for id: UUID) -> URL? {
        folder?.appendingPathComponent(id.uuidString + ".jpg")
    }

    /// Shrinks, turns gray and saves the photo. Returns its new id.
    static func save(_ image: CGImage) throws -> UUID {
        let id = UUID()
        try store(compress(image), for: id)
        return id
    }

    static func store(_ data: Data, for id: UUID) throws {
        guard let url = url(for: id) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func data(for id: UUID) -> Data? {
        url(for: id).flatMap { try? Data(contentsOf: $0) }
    }

    /// Decodes at most `longEdge` pixels on the long side, so a photo from another phone with
    /// huge dimensions can't use up the phone's memory.
    static func image(for id: UUID) -> CGImage? {
        guard let data = data(for: id), isAcceptable(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longEdge),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A photo from another phone is kept only if it's a single JPEG of a sensible size.
    static func isAcceptable(_ data: Data) -> Bool {
        guard data.count <= 400_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return (1...SyncLimits.maxReceiptPixels).contains(width) && (1...SyncLimits.maxReceiptPixels).contains(height)
    }

    static func delete(_ id: UUID) {
        if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
        if let url = textURL(for: id) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Receipt text

    /// The text read from a receipt, next to its photo. In a shared group this, not the photo,
    /// is what the other phones get (ADR 27), and it's all they keep.
    static func textURL(for id: UUID) -> URL? {
        folder?.appendingPathComponent(id.uuidString + ".receipt")
    }

    static func storeText(_ packed: Data, for id: UUID) throws {
        guard let url = textURL(for: id) else { throw CocoaError(.fileWriteUnknown) }
        try packed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Compressed, as it's sent (`ReceiptText.pack`).
    static func packedText(for id: UUID) -> Data? {
        textURL(for: id).flatMap { try? Data(contentsOf: $0) }
    }

    /// For "Delete all my data".
    static func deleteAll() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    /// Grayscale, at most `longEdge` on the long side, JPEG at falling quality until it fits.
    static func compress(_ image: CGImage) throws -> Data {
        var edge = longEdge
        while true {
            let gray = try grayscale(image, longEdge: edge)
            for quality in [0.6, 0.45, 0.32] {
                let data = try jpeg(gray, quality: quality)
                if data.count <= maxBytes { return data }
            }
            edge *= 0.75
            if edge < 500 { return try jpeg(gray, quality: 0.32) }
        }
    }

    private static func grayscale(_ image: CGImage, longEdge: CGFloat) throws -> CGImage {
        let scale = min(1, longEdge / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return result
    }

    private static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // No metadata: no location, no camera details.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}
