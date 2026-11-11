import SwiftUI
import TakaDeCore

struct ExpensesCard: View {
    let group: ExpenseGroup
    let expenses: [Expense]
    let onOpen: (Expense) -> Void
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
                Button { onOpen(expense) } label: {
                    ExpenseRow(expense: expense, group: group)
                        .padding(.vertical, Spacing.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityHint(Text("Opens the expense to edit or delete it"))
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { onOpen(expense) }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(expense) }
                }
                .accessibilityAction(named: Text("Delete")) { onDelete(expense) }
            }
        }
    }
}
