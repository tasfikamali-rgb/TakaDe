import SwiftUI
import TakaDeCore

/// A tinted pill that always says owe or owed in words, never color alone.
struct BalancePill: View {
    let net: Money
    /// False when the pill describes someone else, so it says "Owes" not "You owe".
    var isMe = true

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Text(isMe ? state.label : state.otherLabel)
            if !net.isZero {
                AmountText(money: net.magnitude, size: .label, color: state.color)
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
