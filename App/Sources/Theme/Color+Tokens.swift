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
}
