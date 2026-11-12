import SwiftUI
import UIKit

/// Type scale from DESIGN.md section 3. Inter Display for display (balances, amounts, titles),
/// Inter for the interface, both with tabular figures for amounts. Inter has no Bengali glyphs,
/// so Bengali text uses Hind Siliguri, and amounts in Bengali digits use its SemiBold. Falls back
/// to the system font if a file isn't bundled. Everything scales with Dynamic Type.
///
/// The styles are computed so they follow the in-app language; RootView rebuilds on a switch.
enum AppFont {
    static var balance: Font { display(48, relativeTo: .largeTitle) }
    static var keypad: Font { display(56, relativeTo: .largeTitle) }
    static var title: Font { display(28, relativeTo: .title) }
    static var headline: Font { text(20, .semibold, relativeTo: .headline) }
    static var body: Font { text(16, .regular, relativeTo: .body) }
    static var bodyEmphasis: Font { text(16, .medium, relativeTo: .body) }
    static var label: Font { text(14, .medium, relativeTo: .subheadline) }
    static var caption: Font { text(12, .medium, relativeTo: .caption) }

    /// Display face. Pass `bengali` for text or digits in Bengali script.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle, bengali: Bool = AppLanguage.usesBengaliScript) -> Font {
        custom(bengali ? "HindSiliguri-SemiBold" : "InterDisplay-SemiBold", size, style)
            ?? .system(size: size, weight: .semibold)
    }

    /// Interface face. Pass `bengali` for text in Bengali script.
    static func text(_ size: CGFloat, _ weight: Font.Weight, relativeTo style: Font.TextStyle, bengali: Bool = AppLanguage.usesBengaliScript) -> Font {
        let family = bengali ? "HindSiliguri" : "Inter"
        let face: String
        switch weight {
        case .semibold, .bold, .heavy, .black: face = "SemiBold"
        case .medium: face = "Medium"
        default: face = "Regular"
        }
        return custom("\(family)-\(face)", size, style) ?? .system(style, weight: weight)
    }

    private static let bundled: Set<String> = Set(UIFont.familyNames.flatMap(UIFont.fontNames(forFamilyName:)))

    private static func custom(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font? {
        guard bundled.contains(name) else { return nil }
        if let cascaded = withBengaliFallback(name, size, style) { return cascaded }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Inter with Hind Siliguri as its fallback, so a Bengali name inside English text uses
    /// Hind instead of the system Bengali face. Scaled for the current Dynamic Type size;
    /// RootView rebuilds when that size changes, so the scale stays current.
    private static func withBengaliFallback(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font? {
        guard name.hasPrefix("Inter"), let base = UIFont(name: name, size: size) else { return nil }
        let hind: String
        switch name {
        case "Inter-Regular": hind = "HindSiliguri-Regular"
        case "Inter-Medium": hind = "HindSiliguri-Medium"
        default: hind = "HindSiliguri-SemiBold"
        }
        guard bundled.contains(hind) else { return nil }
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [UIFontDescriptor(name: hind, size: size)]])
        let font = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: style.uiKitStyle).scaledFont(for: font))
    }
}

private extension Font.TextStyle {
    var uiKitStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

/// AppFont's Inter faces are scaled when they're made, so a view has to be rebuilt to pick
/// up a new Dynamic Type size. RootView does that for the main screens; screens presented
/// over it (sheets and full-screen covers) use this, since they aren't part of that rebuild.
struct RebuildsOnDynamicType: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.id(dynamicTypeSize)
    }
}

extension View {
    func rebuildsOnDynamicType() -> some View { modifier(RebuildsOnDynamicType()) }
}
