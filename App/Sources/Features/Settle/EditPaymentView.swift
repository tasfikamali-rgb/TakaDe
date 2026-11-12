import SwiftUI
import TakaDeCore

/// Fixes a recorded payment: the amount, how it was paid, or the transaction ID. Who paid
/// whom stays, and so does its status. It's still only a record; nothing here moves money
/// or verifies anything. Each save shows in Activity and History as an edit.
struct EditPaymentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup
    let original: Settlement
    /// The group's other payments, to catch a transaction ID typed twice.
    var settlements: [Settlement] = []

    @State private var amountText: String
    @State private var method: SettlementMethod
    @State private var reference: String
    @State private var saveError: String?

    init(group: ExpenseGroup, settlement: Settlement, settlements: [Settlement] = []) {
        self.group = group
        original = settlement
        self.settlements = settlements
        _amountText = State(initialValue: KeypadText.plain(settlement.amount))
        _method = State(initialValue: settlement.method)
        _reference = State(initialValue: settlement.userReference ?? "")
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    LabeledContent {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .font(AppFont.bodyEmphasis)
                            .disabled(!canChangeAmount)
                            .accessibilityLabel(Text("Amount"))
                    } label: {
                        Text("Amount")
                    }
                } header: {
                    Text("\(group.displayName(of: original.from)) paid \(group.displayName(of: original.to))")
                } footer: {
                    if !canChangeAmount {
                        Text("\(group.displayName(of: original.to)) marked this received, so only they can change the amount.")
                    }
                }
                PaymentDetailsSection(isMePaying: original.from == group.me?.id, method: $method, reference: $reference,
                                      duplicateWarning: duplicateWarning)
                if let saveError {
                    Section { Text(verbatim: saveError).foregroundStyle(Color.owe) }
                }
            }
            .navigationTitle("Edit payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(edited == nil) }
            }
        }
    }

    private var canChangeAmount: Bool {
        Settlement.canChangeAmount(status: original.status, to: original.to, by: group.me?.id)
    }

    private var amount: Money? {
        guard let value = try? Money.parse(amountText, currency: original.amount.currency), value.minorUnits > 0 else { return nil }
        return value
    }

    /// The payment with the changes, or nil when the amount can't be read or nothing changed.
    private var edited: Settlement? {
        guard let amount else { return nil }
        var copy = original
        let typed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try copy.edit(amount: amount, method: method, userReference: method == .cash || typed.isEmpty ? nil : typed, by: group.me?.id)
        } catch {
            return nil
        }
        return SettlementChange.between(original, copy).isEmpty ? nil : copy
    }

    private var duplicateWarning: String? {
        let others = settlements.filter { $0.id != original.id }
        guard method != .cash, Settlement.duplicate(ofReference: reference, in: others) != nil else { return nil }
        return String(localized: "This transaction ID is already recorded in this group. One payment can only settle one debt.", bundle: .appLanguage)
    }

    private func save() {
        guard let edited else { return }
        if let duplicateWarning {
            saveError = duplicateWarning
            return
        }
        Task {
            do {
                try await app.record(edited, in: group)
                dismiss()
            } catch {
                saveError = String(localized: "The payment wasn't saved. Check the amount and try again.", bundle: .appLanguage)
            }
        }
    }
}
