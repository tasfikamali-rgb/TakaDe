import SwiftUI
import UIKit

/// Type scale from DESIGN.md section 3. Ranade for display (balances, amounts, titles),
/// Author for the interface. Falls back to the system font if the files aren't bundled
/// (scripts/fetch-fonts.sh). Everything scales with Dynamic Type.
enum AppFont {
    static let balance = ranade(48, relativeTo: .largeTitle)
    static let keypad = ranade(56, relativeTo: .largeTitle)
    static let title = ranade(28, relativeTo: .title)
    static let headline = author(20, .semibold, relativeTo: .headline)
    static let body = author(16, .regular, relativeTo: .body)
    static let bodyEmphasis = author(16, .medium, relativeTo: .body)
    static let label = author(14, .medium, relativeTo: .subheadline)
    static let caption = author(12, .medium, relativeTo: .caption)

    static func ranade(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        custom("Ranade-Medium", size, style) ?? .system(size: size, weight: .medium, design: .rounded)
    }

    static func author(_ size: CGFloat, _ weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Author-Semibold"
        case .medium: name = "Author-Medium"
        default: name = "Author-Regular"
        }
        return custom(name, size, style) ?? .system(style, weight: weight)
    }

    private static func custom(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font? {
        UIFont(name: name, size: size) != nil ? .custom(name, size: size, relativeTo: style) : nil
    }
}
