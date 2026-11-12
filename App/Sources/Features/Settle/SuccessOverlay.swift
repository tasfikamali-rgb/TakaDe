import SwiftUI
import TakaDeCore

/// Full-screen accent confirmation (DESIGN.md section 4.6), edge to edge. Tap anywhere to close.
/// The color fills from the bottom trailing corner, where the swipe ended, then the content settles in.
struct SuccessOverlay: View {
    let amount: Money
    let message: String
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        Button(action: onClose) {
            VStack(spacing: Spacing.l) {
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .semibold))
                    .accessibilityHidden(true)
                AmountText(money: amount, size: .balance, color: .onLime, minorColor: .onLime.opacity(0.8))
                Text(verbatim: message)
                    .font(AppFont.headline)
                    .multilineTextAlignment(.center)
                Text("Tap anywhere to close")
                    .font(AppFont.label)
                    .opacity(0.8)
            }
            .foregroundStyle(Color.onLime)
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.92)
            .background {
                Color.lime
                    .scaleEffect(shown || reduceMotion ? 1 : 0.2, anchor: .bottomTrailing)
                    .opacity(shown ? 1 : 0)
                    .ignoresSafeArea()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(Motion.standard(reduceMotion: reduceMotion)) { shown = true }
        }
    }
}
