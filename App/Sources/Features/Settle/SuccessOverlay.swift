import SwiftUI
import TakaDeCore

/// Full-screen lime confirmation (DESIGN.md section 4.6). Tap anywhere to close.
struct SuccessOverlay: View {
    let amount: Money
    let message: String
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            VStack(spacing: Spacing.l) {
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .semibold))
                    .accessibilityHidden(true)
                AmountText(money: amount, size: .balance, color: .onLime, minorColor: .onLime.opacity(0.6))
                Text(verbatim: message)
                    .font(AppFont.headline)
                    .multilineTextAlignment(.center)
                Text("Tap anywhere to close")
                    .font(AppFont.label)
                    .opacity(0.7)
            }
            .foregroundStyle(Color.onLime)
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.lime.ignoresSafeArea())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isModal)
    }
}
