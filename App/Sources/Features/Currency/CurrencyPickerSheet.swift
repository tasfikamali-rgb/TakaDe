import SwiftUI
import TakaDeCore

/// Pick the currency the header's toggle switches to. Searchable by name in Bangla or
/// English, by code or by sign. Only currencies with a rate today are listed once rates
/// have arrived; before that, every current currency is.
struct CurrencyPickerSheet: View {
    @Binding var selection: String
    let available: [String]
    let onPick: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    private var suggested: [String] {
        CurrencyCatalog.suggested.filter { available.contains($0) && CurrencyCatalog.matches($0, query: query, in: locale) }
    }

    private var others: [String] {
        available.filter { !CurrencyCatalog.suggested.contains($0) && CurrencyCatalog.matches($0, query: query, in: locale) }
            .sorted { CurrencyCatalog.name($0, in: locale).localizedStandardCompare(CurrencyCatalog.name($1, in: locale)) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if suggested.isEmpty && others.isEmpty {
                    Text("No currency matches that")
                        .foregroundStyle(Color.inkMuted)
                        .listRowBackground(Color.surface)
                }
                if !suggested.isEmpty {
                    Section("Popular") { ForEach(suggested, id: \.self, content: row) }
                }
                if !others.isEmpty {
                    Section("All currencies") { ForEach(others, id: \.self, content: row) }
                }
            }
            .texturedBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search currencies"))
            .autocorrectionDisabled()
            .navigationTitle("Show balance in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func row(_ code: String) -> some View {
        let isOn = code == selection
        return Button {
            selection = code
            onPick()
            dismiss()
        } label: {
            HStack(spacing: Spacing.s) {
                Text(verbatim: CurrencyCatalog.symbol(code))
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 44, height: 36)
                    .background(Circle().fill(Color.ink.opacity(0.06)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: CurrencyCatalog.name(code, in: locale))
                        .font(AppFont.body)
                        .foregroundStyle(Color.ink)
                    Text(verbatim: code)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .listRowBackground(Color.surface)
    }
}
