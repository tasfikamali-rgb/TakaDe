import SwiftUI
import TakaDeCore

struct SettlementRow: View {
    let settlement: Settlement
    let group: ExpenseGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text("\(group.displayName(of: settlement.from)) paid \(group.displayName(of: settlement.to))")
                    .font(AppFont.body)
                Spacer()
                AmountText(money: settlement.amount, font: AppFont.body)
            }
            Text("\(settlement.method.label) · \(settlement.status.explanation)")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
