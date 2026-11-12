import SwiftUI
import TakaDeCore

/// The dark wallet header (DESIGN.md section 4.2). One job: where you stand overall.
struct HomeHeader: View {
    let total: Money
    let hasGroups: Bool
    let onAddExpense: () -> Void
    let onNewGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Spacer()
                QuickSettingsMenu()
            }
            if hasGroups {
            HStack {
                Text(BalanceState(total).totalLabel)
                    .font(AppFont.label)
                    .foregroundStyle(Color.onHeader.opacity(0.72))
                Spacer()
                CurrencyChip(currency: total.currency)
            }
            AmountText(money: total.magnitude, size: .balance, color: .onHeader, minorColor: .onHeader.opacity(0.6))
            HStack(spacing: Spacing.s) {
                Button("Add expense", systemImage: "plus", action: onAddExpense)
                    .buttonStyle(HeaderPillButtonStyle(filled: true))
                Button("New group", systemImage: "person.2", action: onNewGroup)
                    .buttonStyle(HeaderPillButtonStyle(filled: false))
            }
            .padding(.top, Spacing.xs)
            } else {
                Text("Split costs with friends and see who pays whom")
                    .font(AppFont.title)
                    .foregroundStyle(Color.onHeader)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.huge + Radius.sheet)
        // HomeOverview paints the header color (with its moving glow) behind this.
    }
}
