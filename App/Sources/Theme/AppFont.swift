import SwiftUI
import UIKit

/// Type scale from DESIGN.md section 3. Uses Ranade and Author when bundled
/// (scripts/fetch-fonts.sh) and the system font otherwise. Scales with Dynamic Type.
enum AppFont {
    static let balance = make("Ranade-Medium", 48, .largeTitle, fallback: .medium, design: .rounded)
    static let keypad = make("Ranade-Medium", 56, .largeTitle, fallback: .medium, design: .rounded)
    static let title = make("Ranade-Medium", 28, .title, fallback: .semibold, design: .rounded)
    static let headline = make("Author-Semibold", 20, .headline, fallback: .semibold)
    static let body = make("Author-Regular", 16, .body, fallback: .regular)
    static let bodyEmphasis = make("Author-Medium", 16, .body, fallback: .medium)
    static let label = make("Author-Medium", 14, .subheadline, fallback: .medium)
    static let caption = make("Author-Medium", 12, .caption, fallback: .medium)

    private static func make(_ name: String, _ size: CGFloat, _ style: Font.TextStyle, fallback weight: Font.Weight, design: Font.Design = .default) -> Font {
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: design, weight: weight)
    }
}
