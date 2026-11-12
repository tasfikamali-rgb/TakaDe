import SwiftUI
import UIKit

/// A flag emoji drawn as a picture. A flag is a colourful image, but as Text the
/// accessibility audit measures its colours as text contrast and fails it, with no element
/// to name because the rows around it hide it from VoiceOver. Drawn as an Image, it's
/// treated like the decorative picture it is. Scales with the text size.
struct FlagImage: View {
    let emoji: String
    @ScaledMetric private var side: CGFloat

    init(_ emoji: String, size: CGFloat, relativeTo style: Font.TextStyle = .body) {
        self.emoji = emoji
        _side = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    var body: some View {
        Image(uiImage: FlagImageCache.image(for: emoji))
            .resizable()
            .scaledToFit()
            .frame(height: side * 1.2)
            .accessibilityHidden(true)
    }
}

@MainActor
private enum FlagImageCache {
    private static var images: [String: UIImage] = [:]

    static func image(for emoji: String) -> UIImage {
        if let image = images[emoji] { return image }
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 96)]
        let text = emoji as NSString
        let size = text.size(withAttributes: attributes)
        let image = UIGraphicsImageRenderer(size: CGSize(width: ceil(size.width), height: ceil(size.height))).image { _ in
            text.draw(at: .zero, withAttributes: attributes)
        }
        images[emoji] = image
        return image
    }
}
