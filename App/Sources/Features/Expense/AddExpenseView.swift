import SwiftUI
import TakaDeCore

struct AddExpenseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExpenseDraft
    @State private var showingKeypad = false
    @State private var saveError: String?

    init(group: ExpenseGroup) {
        _draft = State(initialValue: ExpenseDraft(group: group))
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
            }
            .readableWidth()
            .navigationTitle("Add expense")
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
            .onAppear(perform: openKeypadIfEmpty)
        }
    }

    private func openKeypad() { showingKeypad = true }

    private func openKeypadIfEmpty() {
        if draft.amountExpression.isEmpty { showingKeypad = true }
    }

    private func cancel() { dismiss() }

    private func save() {
        Task {
            do {
                try await app.save(try draft.makeExpense(), in: draft.group)
                dismiss()
            } catch {
                saveError = String(localized: "The expense wasn't saved. Check the amounts and try again.")
            }
        }
    }
}

#Preview {
    let group = ExpenseGroup(name: "Sajek trip", members: [Member(displayName: "Sabit", isMe: true), Member(displayName: "Rishan"), Member(displayName: "Nafisa")])
    AddExpenseView(group: group).environment(AppModel.preview())
}
