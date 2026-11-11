import SwiftUI
import TakaDeCore

struct ExpensesSection: View {
    let group: ExpenseGroup
    let expenses: [Expense]
    let onDelete: (Expense) -> Void

    var body: some View {
        Section("Expenses") {
            if expenses.isEmpty {
                Text("Nothing added yet").foregroundStyle(Color.inkMuted)
            }
            ForEach(expenses) { expense in
                ExpenseRow(expense: expense, group: group)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(expense) }
                    }
            }
        }
    }
}
