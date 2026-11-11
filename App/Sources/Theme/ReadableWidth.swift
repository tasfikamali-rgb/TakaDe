import SwiftUI

/// Keeps forms and lists from stretching edge to edge on iPad and wide windows,
/// while staying full width on phones.
struct ReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Spacing.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth() -> some View { modifier(ReadableWidth()) }
}
