import PhotosUI
import SwiftUI
import TakaDeCore
import UIKit

/// A group's cover photo (Sabit, 2026-11-12): a wide banner across the top of the group,
/// like a cover photo on a profile. The group's round icon comes from its name instead
/// (`GroupIcon`). It's a file on this phone next to the ledger, one per group, picked with
/// the system photo picker (no photo library permission). It isn't uploaded yet: shared
/// groups get the photo's colour, not the photo, until the sync service carries encrypted
/// photos.
enum GroupPhotoFile {
    /// Width over height. Wide like a cover photo; a photo saved before covers existed is
    /// square and is simply cropped to fit.
    static let aspect: CGFloat = 2
    /// Wide enough for an iPad header, small enough to load instantly (about 100 KB).
    static let width: CGFloat = 1200

    static var directory: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("GroupPhotos", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }

    static func url(for group: GroupID) -> URL? {
        directory?.appendingPathComponent("\(group.description).jpg")
    }

    static func load(_ group: GroupID) -> UIImage? {
        guard let url = url(for: group), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Crops to a centred 2:1 banner, shrinks it, saves it as JPEG and returns the photo's
    /// main colour. Runs off the main thread; photos can be large.
    static func save(_ data: Data, for group: GroupID) async throws -> (image: UIImage, accentHex: String?) {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // The largest 2:1 rectangle inside the photo, then shrunk to at most `width`.
            let cropWidth = min(image.size.width, image.size.height * Self.aspect)
            let scale = min(1, Self.width / cropWidth)
            let target = CGSize(width: (cropWidth * scale).rounded(), height: (cropWidth / Self.aspect * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
            }
            guard let jpeg = square.jpegData(compressionQuality: 0.82), let url = Self.url(for: group) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return (square, DominantColor.hex(of: square))
        }.value
    }

    static func remove(_ group: GroupID) {
        guard let url = url(for: group) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Used by Delete all my data.
    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The most prominent colour in a photo: the hue that covers the most of it, counting
/// colourful pixels more than greys. A photo that's mostly grey, black or white has none,
/// and the group keeps the standard lilac.
enum DominantColor {
    static func hex(of image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var red = [Double](repeating: 0, count: bins)
        var green = [Double](repeating: 0, count: bins)
        var blue = [Double](repeating: 0, count: bins)
        var colourful = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let brightness = maxC
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            // Greys, near-black and blown-out pixels say nothing about the colour.
            guard saturation > 0.18, brightness > 0.18 else { continue }
            var hue: Double
            let delta = maxC - minC
            if maxC == r { hue = (g - b) / delta } else if maxC == g { hue = 2 + (b - r) / delta } else { hue = 4 + (r - g) / delta }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let bin = min(bins - 1, Int(hue * Double(bins)))
            let w = saturation * brightness
            weight[bin] += w
            red[bin] += r * w
            green[bin] += g * w
            blue[bin] += b * w
            colourful += 1
        }
        // Under a tenth of the photo colourful: treat it as a grey photo.
        guard colourful >= Double(side * side) * 0.1, let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else {
            return nil
        }
        let w = weight[best]
        return String(format: "#%02X%02X%02X", Int(red[best] / w * 255), Int(green[best] / w * 255), Int(blue[best] / w * 255))
    }
}

/// A group's background colour. With an accent from its photo it's a soft version of that
/// hue: light and pale in light mode, deep and muted in dark mode, so the usual ink text
/// keeps strong contrast either way. Without one it's the standard lilac.
enum GroupTint {
    static func color(for group: ExpenseGroup) -> Color {
        guard let hex = group.accentHex, let hue = hue(of: hex) else { return .lilac }
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hue: hue, saturation: 0.40, brightness: 0.30, alpha: 1)
                : UIColor(hue: hue, saturation: 0.24, brightness: 0.93, alpha: 1)
        })
    }

    private static func hue(of hex: String) -> CGFloat? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let color = UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        var hue: CGFloat = 0
        guard color.getHue(&hue, saturation: nil, brightness: nil, alpha: nil) else { return nil }
        return hue
    }
}

/// The group's round icon: an emoji picked from its name ("Car" shows 🚗), or the TakaDe
/// mark when nothing matches. Nobody chooses it; renaming the group changes it.
struct GroupIconBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    var size: CGFloat = 32
    var fill: Color = .surface
    var ring: Color = .surface

    var body: some View {
        let emoji = GroupIcon.emoji(for: name)
        ZStack {
            Circle().fill(fill)
            if let emoji {
                Text(verbatim: emoji)
                    .font(.system(size: size * 0.5))
                    // Pops in as the name is typed; a plain fade with Reduce Motion.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    .id(emoji)
            } else {
                TakaMark(split: 1)
                    .foregroundStyle(Color("launchMark"))
                    .frame(width: size * 0.58, height: size * 0.58)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(ring, lineWidth: 2))
        .animation(Motion.momentum(reduceMotion: reduceMotion), value: emoji)
        // The group's name always sits next to it, so VoiceOver skips the picture.
        .accessibilityHidden(true)
    }
}

/// The cover photo as a full-width banner.
struct GroupCoverImage: View {
    let photo: UIImage
    var height: CGFloat = 150

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { Image(uiImage: photo).resizable().scaledToFill() }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(Text("Cover photo"))
            .accessibilityAddTraits(.isImage)
    }
}

/// Add, change or remove a group's cover photo.
struct GroupPhotoPicker<Label: View>: View {
    let hasPhoto: Bool
    let onPick: (Data) -> Void
    let onRemove: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var item: PhotosPickerItem?
    @State private var choosing = false

    var body: some View {
        Group {
            if hasPhoto {
                Menu {
                    Button("Change cover photo", systemImage: "photo") { choosing = true }
                    Button("Remove cover photo", systemImage: "trash", role: .destructive, action: onRemove)
                } label: { label() }
            } else {
                Button { choosing = true } label: { label() }
            }
        }
        .photosPicker(isPresented: $choosing, selection: $item, matching: .images)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                defer { item = nil }
                if let data = try? await picked.loadTransferable(type: Data.self) { onPick(data) }
            }
        }
    }
}
