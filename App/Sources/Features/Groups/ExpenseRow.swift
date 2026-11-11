import SwiftUI
import TakaDeCore

/// Transaction row from the wallet reference: avatar in a soft circle, title, who paid,
/// amount right aligned and large.
struct ExpenseRow: View {
    let expense: Expense
    let group: ExpenseGroup

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let category = expense.category {
                CategoryBadge(category: category)
            } else {
                Avatar(name: expense.paidBy.keys.map(group.storedName(of:)).sorted().first ?? "?", size: 36)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: expense.title).font(AppFont.bodyEmphasis)
                Text("Paid by \(payerNames.formatted(.list(type: .and)))")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            AmountText(money: expense.total, size: .headline)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var payerNames: [String] {
        expense.paidBy.keys.map(group.displayName(of:)).sorted()
    }
}
