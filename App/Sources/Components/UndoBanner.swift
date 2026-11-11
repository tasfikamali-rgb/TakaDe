import SwiftUI

/// A short-lived bar with an Undo action, used instead of a confirmation dialog.
struct UndoBanner: View {
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
                .foregroundStyle(Color.lime)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, Spacing.m)
        .background(Capsule().fill(Color.header))
        .accessibilityElement(children: .contain)
    }
}
