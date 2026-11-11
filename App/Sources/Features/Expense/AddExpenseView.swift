import SwiftUI
import TakaDeCore

struct AddExpenseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExpenseDraft
    @State private var showingKeypad = false
    @State private var saveError: String?
    @State private var confirmingDelete = false
    private let onDelete: ((Expense) -> Void)?

    init(group: ExpenseGroup) {
        _draft = State(initialValue: ExpenseDraft(group: group))
        onDelete = nil
    }

    /// Opens a saved expense to change it, with Delete at the bottom.
    init(editing expense: Expense, in group: ExpenseGroup, onDelete: @escaping (Expense) -> Void) {
        _draft = State(initialValue: ExpenseDraft(editing: expense, in: group))
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(draft: draft, onTap: openKeypad)
                    TextField("What was it for?", text: $draft.title)
                    DatePicker("Date", selection: $draft.occurredAt, displayedComponents: .date)
                    ReceiptScanButton(onReviewed: draft.apply)
                }

                Section {
                    Picker("Paid by", selection: $draft.payer) {
                        ForEach(draft.group.members) { member in
                            Text(verbatim: draft.group.displayName(of: member.id)).tag(member.id)
                        }
                    }
                }

                SplitSection(draft: draft)

                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.owe) }
                }

                if draft.original != nil, onDelete != nil {
                    Section {
                        Button("Delete expense", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .readableWidth()
            .navigationTitle(draft.isEditing ? "Edit expense" : "Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!draft.canSave)
                }
            }
            .sheet(isPresented: $showingKeypad) {
                AmountKeypadSheet(expression: $draft.amountExpression, currency: draft.group.currency)
                    .presentationDetents([.large])
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteExpense)
            } message: {
                Text("You can undo right after")
            }
            .onAppear(perform: openKeypadIfEmpty)
            .interactiveDismissDisabled(draft.hasContent)
        }
    }

    private func openKeypad() { showingKeypad = true }

    private func openKeypadIfEmpty() {
        if draft.amountExpression.isEmpty { showingKeypad = true }
    }

    private func cancel() { dismiss() }

    private func deleteExpense() {
        guard let original = draft.original else { return }
        dismiss()
        onDelete?(original)
    }

    private func save() {
        Task {
            do {
                try await app.save(try draft.makeExpense(), in: draft.group)
                dismiss()
            } catch {
                saveError = String(localized: "The expense wasn't saved. Check the amounts and try again.", bundle: .appLanguage)
            }
        }
    }
}

#Preview {
    let group = ExpenseGroup(name: "Sajek trip", members: [Member(displayName: "Sabit", isMe: true), Member(displayName: "Rishan"), Member(displayName: "Nafisa")])
    AddExpenseView(group: group).environment(AppModel.preview())
}
