import SwiftUI

/// A short-lived bar with an Undo action, used instead of a confirmation dialog.
struct UndoBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(verbatim: message)
                .font(AppFont.label)
                .foregroundStyle(Color.onHeader)
                .lineLimit(2)
            Spacer(minLength: Spacing.s)
            Button("Undo", action: onUndo)
                .font(AppFont.label.weight(.semibold))
                .foregroundStyle(Color.onLime)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 36)
                .background(Capsule().fill(Color.lime))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, Spacing.xs)
        .background(Capsule().fill(Color.header))
        // Light mode has no dark surfaces, so the bar lifts off the page with a shadow instead.
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.14), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}
