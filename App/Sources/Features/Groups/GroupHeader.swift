import SwiftUI
import TakaDeCore

/// Lilac header for a group (DESIGN.md section 2, optional group tint).
struct GroupHeader: View {
    let group: ExpenseGroup
    /// Nil while loading, so the header doesn't flash "Settled up".
    let myNet: Money?
    let onAddExpense: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            AvatarStack(names: group.members.map(\.displayName), size: 32, ring: .lilac, fill: .surface)
            Text(verbatim: group.name)
                .font(AppFont.title)
                .tracking(-0.02 * 28)
                .foregroundStyle(Color.ink)
            if let myNet {
                let state = BalanceState(myNet)
                Text(state.label)
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink.opacity(0.72))
                    .padding(.top, Spacing.xs)
                if state != .settled {
                    AmountText(money: myNet.magnitude, size: .balance, color: .ink, minorColor: .ink.opacity(0.6))
                }
            }
            Button("Add expense", systemImage: "plus", action: onAddExpense)
                .buttonStyle(HeaderPillButtonStyle(filled: true, fill: .ink, text: .lilac))
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.huge + Radius.sheet)
        .background(Color.lilac)
    }
}
