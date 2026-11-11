import SwiftUI
import TakaDeCore

struct ExpenseRow: View {
    let expense: Expense
    let group: ExpenseGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: expense.title).font(AppFont.body)
                Text("Paid by \(payerNames)")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            AmountText(money: expense.total, font: AppFont.bodyEmphasis)
        }
        .accessibilityElement(children: .combine)
    }

    private var payerNames: String {
        expense.paidBy.keys.map(group.displayName(of:)).sorted().formatted(.list(type: .and))
    }
}
