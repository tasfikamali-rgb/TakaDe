import SwiftUI
import UIKit

/// Type scale from DESIGN.md section 3. Ranade for display (balances, amounts, titles),
/// Author for the interface. Neither has Bengali glyphs, so Bengali text uses Hind Siliguri,
/// and amounts in Bengali digits use its SemiBold in place of Ranade. Falls back to the
/// system font if a file isn't bundled. Everything scales with Dynamic Type.
///
/// The styles are computed so they follow the in-app language; RootView rebuilds on a switch.
enum AppFont {
    static var balance: Font { ranade(48, relativeTo: .largeTitle) }
    static var keypad: Font { ranade(56, relativeTo: .largeTitle) }
    static var title: Font { ranade(28, relativeTo: .title) }
    static var headline: Font { author(20, .semibold, relativeTo: .headline) }
    static var body: Font { author(16, .regular, relativeTo: .body) }
    static var bodyEmphasis: Font { author(16, .medium, relativeTo: .body) }
    static var label: Font { author(14, .medium, relativeTo: .subheadline) }
    static var caption: Font { author(12, .medium, relativeTo: .caption) }

    /// Display face. Pass `bengali` for text or digits in Bengali script.
    static func ranade(_ size: CGFloat, relativeTo style: Font.TextStyle, bengali: Bool = AppLanguage.usesBengaliScript) -> Font {
        custom(bengali ? "HindSiliguri-SemiBold" : "Ranade-Medium", size, style)
            ?? .system(size: size, weight: .medium, design: .rounded)
    }

    /// Interface face. Pass `bengali` for text in Bengali script.
    static func author(_ size: CGFloat, _ weight: Font.Weight, relativeTo style: Font.TextStyle, bengali: Bool = AppLanguage.usesBengaliScript) -> Font {
        let family = bengali ? "HindSiliguri" : "Author"
        let face: String
        switch weight {
        case .semibold, .bold, .heavy, .black: face = bengali ? "SemiBold" : "Semibold"
        case .medium: face = "Medium"
        default: face = "Regular"
        }
        return custom("\(family)-\(face)", size, style) ?? .system(style, weight: weight)
    }

    private static let bundled: Set<String> = Set(UIFont.familyNames.flatMap(UIFont.fontNames(forFamilyName:)))

    private static func custom(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font? {
        bundled.contains(name) ? .custom(name, size: size, relativeTo: style) : nil
    }
}
