import SwiftUI
import PhotosUI
import UIKit

/// The owner's profile picture. It stays on this phone, in a protected file next to the
/// ledger: it isn't uploaded, put in the account, the export or other people's groups.
/// Picked with the system photo picker, which needs no photo library permission.
enum ProfilePhotoFile {
    /// Square, so it fills the round avatar; small enough to load instantly.
    static let side: CGFloat = 512

    static var url: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Profile", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir.appendingPathComponent("photo.jpg")
    }

    static func load() -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Crops the picked image to a centred square, shrinks it and saves it as JPEG.
    /// Runs off the main thread; photos can be large.
    static func save(_ data: Data) async throws -> UIImage {
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
            guard let jpeg = square.jpegData(compressionQuality: 0.85), let url = Self.url else { throw CocoaError(.fileWriteUnknown) }
            try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return square
        }.value
    }

    static func remove() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// A round avatar that shows the profile picture when there is one, otherwise the first
/// letter of the name, otherwise a person outline (never a question mark).
struct ProfileAvatar: View {
    let name: String
    let photo: UIImage?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else if let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first {
                Text(verbatim: String(initial))
                    .font(AppFont.text(size * 0.42, .semibold, relativeTo: .body))
                    .foregroundStyle(Color.ink)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color.ink.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        // A plain surface with an edge, so the spot stands out on the tinted Account header
        // instead of blending into it (Sabit, 2026-11-12).
        .background(Circle().fill(Color.surface))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.ink.opacity(photo == nil ? 0.16 : 0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The avatar with a camera badge. Tapping it picks a photo; when there is one, a menu
/// also offers to remove it.
struct ProfilePhotoPicker: View {
    @Environment(AccountModel.self) private var account
    let name: String
    var size: CGFloat = 96

    @State private var item: PhotosPickerItem?
    @State private var choosing = false
    @State private var failed = false
    @State private var fetchingGoogle = false

    var body: some View {
        Group {
            if account.photo == nil && !account.canUseGooglePhoto {
                Button { choosing = true } label: { badged }
            } else {
                Menu {
                    Button(account.photo == nil ? "Choose a photo" : "Choose a new photo", systemImage: "photo") { choosing = true }
                    if account.canUseGooglePhoto {
                        Button("Use my Google photo", systemImage: "person.crop.circle.badge.checkmark", action: useGooglePhoto)
                    }
                    if account.photo != nil {
                        Button("Remove photo", systemImage: "trash", role: .destructive) { account.removePhoto() }
                    }
                } label: { badged }
            }
        }
        .overlay {
            if fetchingGoogle { ProgressView() }
        }
        .buttonStyle(PressScaleButtonStyle())
        .photosPicker(isPresented: $choosing, selection: $item, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                do {
                    guard let data = try await picked.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
                    try await account.setPhoto(data)
                } catch {
                    failed = true
                }
                item = nil
            }
        }
        .alert("That photo couldn't be used. Try another one.", isPresented: $failed) {}
        .accessibilityLabel(account.photo == nil ? Text("Add a profile photo") : Text("Change profile photo"))
    }

    private func useGooglePhoto() {
        fetchingGoogle = true
        Task {
            defer { fetchingGoogle = false }
            do {
                try await account.useGooglePhoto()
            } catch is CancellationError {
                // Closed the Google sheet.
            } catch {
                failed = true
            }
        }
    }

    private var badged: some View {
        ProfileAvatar(name: name, photo: account.photo, size: size)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: account.photo == nil ? "camera.fill" : "pencil")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(Color.onLime)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Circle().fill(Color.lime))
                    .overlay(Circle().stroke(Color.canvas, lineWidth: 3))
                    .offset(x: 2, y: 2)
            }
            .frame(minWidth: 44, minHeight: 44)
    }
}
