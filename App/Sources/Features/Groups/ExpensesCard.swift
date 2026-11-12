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
                HStack(spacing: Spacing.xxs) {
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
                    // A visible Edit, so nobody has to guess that the row opens (Sabit, 2026-11-12).
                    EditIconButton(label: Text("Edit \(expense.title)")) { onOpen(expense) }
                }
            }
        }
    }
}

/// A small pencil beside a row: 44 points to tap, quiet so the amount stays the focus.
struct EditIconButton: View {
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(AppFont.label)
                .foregroundStyle(Color.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.ink.opacity(0.06)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}
