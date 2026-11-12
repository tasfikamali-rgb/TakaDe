import SwiftUI

/// Color tokens from DESIGN.md section 2. Defined in Assets.xcassets with light and dark
/// variants (contrast-checked to WCAG AA); never hard-code hex in views.
extension Color {
    static let canvas = Color("canvas")
    static let surface = Color("surface")
    static let surfaceRaised = Color("surfaceRaised")
    /// Your own cards in Activity: a soft tint of the blue accent, so they stand apart from
    /// the canvas and from friends' white cards in light mode (surfaceRaised blended in).
    static let surfaceMine = Color("surfaceMine")
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
    /// Switches when on: the blue accent, a step softer in dark mode.
    static let toggleOn = Color("toggleOn")
}

/// Tab bar roles. The bar reads only these, so a new palette is a change here (or a new
/// colorset), not in the bar's code.
extension Color {
    static let tabBarBackground = Color.header
    static let tabBarIndicator = Color.lime
    static let tabBarSelected = Color.onLime
    /// Solid, not faded: at 78% opacity the small labels failed the accessibility audit's
    /// contrast check ("Activity" on Settings, 2026-11-12). The selected tab still stands
    /// out on its accent pill.
    static let tabBarUnselected = Color.onHeader
}

/// The moving line texture behind every screen (`FlowingLines`): ink hairlines at a few
/// percent. Its opacity lives in the colorset.
extension Color {
    static let texture = Color("texture")
}
