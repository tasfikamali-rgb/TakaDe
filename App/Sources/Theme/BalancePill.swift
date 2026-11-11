import SwiftUI
import TakaDeCore

/// A tinted pill that always says owe or owed in words, never color alone.
struct BalancePill: View {
    let net: Money

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Text(state.label)
            if !net.isZero {
                AmountText(money: net.magnitude, font: AppFont.label, color: state.color)
            }
        }
        .font(AppFont.label)
        .foregroundStyle(state.color)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 6)
        .background(Capsule().fill(state.tint))
    }

    private var state: BalanceState { BalanceState(net) }
}
