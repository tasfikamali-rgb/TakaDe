import SwiftUI
import TakaDeCore

struct ExpensesCard: View {
    let group: ExpenseGroup
    let expenses: [Expense]
    let onDelete: (Expense) -> Void

    var body: some View {
        SectionCard(title: "Expenses") {
            if expenses.isEmpty {
                Text("Nothing added yet")
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.s)
            }
            ForEach(expenses) { expense in
                ExpenseRow(expense: expense, group: group)
                    .padding(.vertical, Spacing.xxs)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(expense) }
                    }
                    .accessibilityAction(named: Text("Delete")) { onDelete(expense) }
            }
        }
    }
}
