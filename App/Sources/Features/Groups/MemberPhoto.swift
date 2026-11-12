import SwiftUI
import TakaDeCore
import UIKit

/// A group member's photo, taken from their contact card when they're added from Contacts
/// (Sabit, 2026-11-12). It's a small file on this phone, one per member, next to the ledger.
/// It isn't in the database, the export or a shared group's sync, so other people in the
/// group never get it. Delete all my data and removing the person delete it.
enum MemberPhotoFile {
    /// Avatars are at most about 40 points, so 256 pixels is sharp on every screen.
    static let side: CGFloat = 256

    static var directory: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MemberPhotos", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }

    static func url(for member: MemberID) -> URL? {
        directory?.appendingPathComponent("\(member.description).jpg")
    }

    static func read(_ member: MemberID) -> UIImage? {
        guard let url = url(for: member), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Crops to a centred square, shrinks it and saves it as JPEG. Runs off the main thread.
    static func save(_ data: Data, for member: MemberID) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let shortest = min(image.size.width, image.size.height)
            let scale = min(1, Self.side / shortest)
            let target = CGSize(width: shortest * scale, height: shortest * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
            }
            guard let jpeg = square.jpegData(compressionQuality: 0.85), let url = Self.url(for: member) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return square
        }.value
    }

    static func remove(_ member: MemberID) {
        guard let url = url(for: member) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Used by Delete all my data.
    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Member photos already read, so lists don't read the same file again while scrolling.
/// It also remembers who has no photo, which is most people.
@MainActor
enum MemberPhotos {
    private static var images: [MemberID: UIImage] = [:]
    private static var missing: Set<MemberID> = []

    static func cached(_ member: MemberID) -> UIImage? { images[member] }

    static func load(_ member: MemberID) async -> UIImage? {
        if let image = images[member] { return image }
        if missing.contains(member) { return nil }
        let image = await Task.detached(priority: .utility) { MemberPhotoFile.read(member) }.value
        if let image { images[member] = image } else { missing.insert(member) }
        return image
    }

    static func didSave(_ image: UIImage, for member: MemberID) {
        images[member] = image
        missing.remove(member)
    }

    static func didRemove(_ member: MemberID) {
        images[member] = nil
        missing.insert(member)
    }

    static func reset() {
        images = [:]
        missing = []
    }
}

/// A member's avatar: their contact photo when there is one, then the photo of a TakaDe
/// friend with exactly their name, otherwise their initial.
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 36

    @Environment(SocialModel.self) private var social: SocialModel?
    @State private var photo: UIImage?

    var body: some View {
        Avatar(name: member.displayName, size: size, photo: photo ?? MemberPhotos.cached(member.id) ?? fallback)
            .task(id: member.id) { photo = await MemberPhotos.load(member.id) }
    }

    private var fallback: UIImage? {
        member.isMe ? nil : social?.photo(forName: member.displayName)
    }
}
