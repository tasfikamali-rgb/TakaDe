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
            LayeredForm {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: draft.group.name)
                        .font(AppFont.label)
                        .foregroundStyle(Color.ink.opacity(0.72))
                        .lineLimit(1)
                    AmountField(draft: draft, size: .balance, onTap: openKeypad)
                    // A new expense with no amount starts on three big choices; after
                    // that, scanning stays one small row under the amount.
                    if startsWithChoices {
                        ReceiptScanButton(onReviewed: draft.apply, onEnterAmount: openKeypad, onPhoto: draft.attach)
                            .padding(.top, Spacing.xs)
                    } else {
                        ReceiptScanButton(onReviewed: draft.apply, onPhoto: draft.attach)
                            .font(AppFont.label)
                            .tint(Color.ink)
                    }
                }
            } content: {
                Section {
                    TextField("What was it for?", text: $draft.title)
                    DatePicker("Date", selection: $draft.occurredAt, displayedComponents: .date)
                    // A monthly copy follows its original, so only the original can repeat.
                    if draft.original?.repeatOf == nil {
                        Toggle("Repeat every month", isOn: $draft.repeatsMonthly)
                    }
                    Picker(selection: $draft.category) {
                        Text("None").tag(ExpenseCategory?.none)
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            Label(category.label, systemImage: category.systemImage).tag(Optional(category))
                        }
                    } label: {
                        Text("Category")
                    }
                }

                if draft.hasReceipt {
                    ReceiptPhotoSection(draft: draft)
                }

                PaidBySection(draft: draft)

                SplitSection(draft: draft)

                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.owe) }
                }

                if draft.original != nil, onDelete != nil {
                    Section {
                        Button("Delete expense", role: .destructive) { confirmingDelete = true }
                            .foregroundStyle(Color.owe)
                    }
                }
            }
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
            .interactiveDismissDisabled(draft.hasContent)
        }
    }

    private func openKeypad() { showingKeypad = true }

    private var startsWithChoices: Bool {
        !draft.isEditing && draft.amountExpression.isEmpty
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
                // The photo is saved on the phone first, so the expense never points to nothing.
                if let photo = draft.newReceipt {
                    draft.receiptID = try ReceiptPhotos.save(photo)
                    draft.newReceipt = nil
                }
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
    let app = AppModel.preview()
    return AddExpenseView(group: group).environment(app).environment(GroupSync(app: app, config: nil))
}
