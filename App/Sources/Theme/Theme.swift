import SwiftUI
import UIKit

/// Color tokens from DESIGN.md section 2. Defined in Assets.xcassets with light and dark
/// variants; never hard-code hex in views.
extension Color {
    static let canvas = Color("canvas")
    static let surface = Color("surface")
    static let surfaceRaised = Color("surfaceRaised")
    static let ink = Color("ink")
    static let inkMuted = Color("inkMuted")
    static let header = Color("header")
    static let onHeader = Color("onHeader")
    static let lime = Color("lime")
    static let onLime = Color("onLime")
    static let owed = Color("owed")
    static let owe = Color("owe")
    static let owedTint = Color("owedTint")
    static let oweTint = Color("oweTint")
    static let bkash = Color("bkash")
    static let sheet = Color("sheet")
}

enum Spacing {
    static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16
    static let l: CGFloat = 20, xl: CGFloat = 24, xxl: CGFloat = 32, huge: CGFloat = 48
    static let screenMargin: CGFloat = 20
}

enum Radius {
    static let sheet: CGFloat = 28, card: CGFloat = 20, key: CGFloat = 16
}

enum Motion {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let sheet = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

/// Type scale from DESIGN.md section 3. Uses Ranade/Author when bundled
/// (run scripts/fetch-fonts.sh) and falls back to the system font otherwise.
enum AppFont {
    private static func custom(_ name: String, _ size: CGFloat, relativeTo style: Font.TextStyle, fallback weight: Font.Weight, design: Font.Design = .default) -> Font {
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: design).weight(weight)
    }

    static let balance = custom("Ranade-Medium", 48, relativeTo: .largeTitle, fallback: .medium, design: .rounded)
    static let keypad = custom("Ranade-Medium", 56, relativeTo: .largeTitle, fallback: .medium, design: .rounded)
    static let title = custom("Ranade-Medium", 28, relativeTo: .title, fallback: .semibold, design: .rounded)
    static let headline = custom("Author-Semibold", 20, relativeTo: .headline, fallback: .semibold)
    static let body = custom("Author-Regular", 16, relativeTo: .body, fallback: .regular)
    static let label = custom("Author-Medium", 14, relativeTo: .subheadline, fallback: .medium)
    static let caption = custom("Author-Medium", 12, relativeTo: .caption, fallback: .medium)
}
