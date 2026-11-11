import SwiftUI
import TakaDeCore

/// OCR is a suggestion. The person checks every field before it fills the expense.
struct ReceiptReviewView: View {
    let suggestion: ReceiptSuggestion
    let onUse: (_ merchant: String?, _ total: Money?, _ date: Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var merchant: String
    @State private var total: Money?
    @State private var date: Date
    @State private var includesDate: Bool

    init(suggestion: ReceiptSuggestion, onUse: @escaping (String?, Money?, Date?) -> Void) {
        self.suggestion = suggestion
        self.onUse = onUse
        _merchant = State(initialValue: suggestion.merchant ?? "")
        _total = State(initialValue: suggestion.total)
        _date = State(initialValue: suggestion.date ?? Date())
        _includesDate = State(initialValue: suggestion.date != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(suggestion.confidence >= 0.8
                         ? LocalizedStringKey("Check these before using them")
                         : LocalizedStringKey("We weren't sure about the total. Pick the right one"))
                        .font(AppFont.body)
                        .foregroundStyle(Color.inkMuted)
                }
                Section("Shop") {
                    TextField("Shop name", text: $merchant)
                }
                Section("Total") {
                    Picker("Total", selection: $total) {
                        ForEach(suggestion.candidateAmounts.prefix(8), id: \.self) { amount in
                            AmountText(money: amount, font: AppFont.body).tag(Optional(amount))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Use the receipt's date", isOn: $includesDate)
                    if includesDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                } footer: {
                    Text("Read on this phone. The photo isn't saved or uploaded.")
                }
            }
            .readableWidth()
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use these", action: use).disabled(total == nil)
                }
            }
        }
    }

    private func cancel() { dismiss() }

    private func use() {
        let name = merchant.trimmingCharacters(in: .whitespaces)
        onUse(name.isEmpty ? nil : name, total, includesDate ? date : nil)
        dismiss()
    }
}
