import SwiftUI
import TakaDeCore

/// OCR is a suggestion. The person checks every field before it fills the expense.
struct ReceiptReviewView: View {
    let suggestion: ReceiptSuggestion
    let image: CGImage?
    let onUse: (_ merchant: String?, _ total: Money?, _ date: Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var merchant: String
    @State private var total: Money?
    @State private var date: Date
    @State private var includesDate: Bool
    @State private var showsItems: Bool

    init(suggestion: ReceiptSuggestion, image: CGImage?, onUse: @escaping (String?, Money?, Date?) -> Void) {
        self.suggestion = suggestion
        self.image = image
        self.onUse = onUse
        _merchant = State(initialValue: suggestion.merchant ?? "")
        _total = State(initialValue: suggestion.total)
        _date = State(initialValue: suggestion.date ?? Date())
        _includesDate = State(initialValue: suggestion.date != nil)
        // Open the items when they don't add up, so the misread line is easy to spot.
        _showsItems = State(initialValue: suggestion.computedTotal.map { $0 != suggestion.total } ?? false)
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    Text(suggestion.confidence >= 0.8
                         ? LocalizedStringKey("Check these before using them")
                         : LocalizedStringKey("We weren't sure about the total. Pick the right one"))
                        .font(AppFont.body)
                        .foregroundStyle(Color.inkMuted)
                }
                if let image {
                    Section {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
                            .accessibilityLabel(Text("Receipt photo"))
                    }
                }
                Section("Shop") {
                    TextField("Shop name", text: $merchant)
                }
                Section("Total") {
                    Picker("Total", selection: $total) {
                        ForEach(suggestion.candidateAmounts.prefix(8), id: \.self) { amount in
                            AmountText(money: amount, size: .body).tag(Optional(amount))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if !suggestion.items.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showsItems) {
                            ForEach(suggestion.items.prefix(40)) { line in
                                ReceiptLineRow(line: line)
                            }
                        } label: {
                            Text("^[\(suggestion.items.count) item](inflect: true)")
                                .font(AppFont.bodyEmphasis)
                                .foregroundStyle(Color.ink)
                        }
                    } header: {
                        Text("Items")
                    } footer: {
                        Text("For checking only. The expense saves the total.")
                    }
                }
                if !suggestion.charges.isEmpty || suggestion.computedTotal != nil {
                    Section("Tax and charges") {
                        ForEach(suggestion.charges) { line in
                            ReceiptLineRow(line: line)
                        }
                        if let total, let computed = suggestion.computedTotal {
                            ReceiptCheckRow(computed: computed, total: total)
                        }
                    }
                }
                Section {
                    if suggestion.date != nil {
                        // Found a date: offer it, and let the person correct a misread.
                        Toggle("Use the receipt's date", isOn: $includesDate)
                        if includesDate {
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        }
                    } else {
                        // Nothing to "use": say so rather than offering today's date.
                        Text("No date found on the receipt. The expense keeps the date you picked.")
                            .foregroundStyle(Color.inkMuted)
                    }
                } footer: {
                    Text("Read on this phone. In a shared group, the others get this text, encrypted, not the photo.")
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
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        onUse(name.isEmpty ? nil : name, total, includesDate ? date : nil)
        dismiss()
    }
}
