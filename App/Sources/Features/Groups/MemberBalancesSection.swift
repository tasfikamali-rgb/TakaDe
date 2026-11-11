import SwiftUI
import TakaDeCore

struct MemberBalancesSection: View {
    let group: ExpenseGroup
    let balances: GroupBalances

    var body: some View {
        Section("Balances") {
            ForEach(group.members) { member in
                HStack {
                    Text(verbatim: group.displayName(of: member.id))
                        .font(AppFont.body)
                    Spacer()
                    BalancePill(net: balances.net(for: member.id))
                }
            }
            if let me = group.me, let unverified = balances.unverifiedSettled[me.id], !unverified.isZero {
                HStack(spacing: Spacing.xxs) {
                    Text("Includes payments you recorded that no provider has verified:")
                    AmountText(money: unverified, font: AppFont.caption, color: .inkMuted)
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            }
        }
    }
}
