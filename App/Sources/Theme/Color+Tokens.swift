import SwiftUI

/// Color tokens from DESIGN.md section 2. Defined in Assets.xcassets with light and dark
/// variants (contrast-checked to WCAG AA); never hard-code hex in views.
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
    static let lilac = Color("lilac")
    /// The slow light behind the Home header: pale periwinkle in light mode, deep blue in dark.
    static let glow = Color("glow")
}

/// Tab bar roles. The bar reads only these, so a new palette is a change here (or a new
/// colorset), not in the bar's code.
extension Color {
    static let tabBarBackground = Color.header
    static let tabBarIndicator = Color.lime
    static let tabBarSelected = Color.onLime
    static let tabBarUnselected = Color.onHeader.opacity(0.62)
}
