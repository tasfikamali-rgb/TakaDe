import SwiftUI

/// Section header text in forms: `inkMuted` in the interface face at semibold. The
/// accessibility audit samples real pixels, and thin 13 pt headers ("LANGUAGE") measured
/// lighter than their color and failed the contrast check even at `#4A4A47`. Semibold strokes
/// are wide enough to show their real color.
struct FormHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppFont.text(13, .semibold, relativeTo: .footnote))
            .foregroundStyle(Color.inkMuted)
    }
}

extension View {
    func formHeader() -> some View { modifier(FormHeader()) }
}
