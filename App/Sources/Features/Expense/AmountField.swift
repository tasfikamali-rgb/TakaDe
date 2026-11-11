import SwiftUI
import TakaDeCore

/// Shows the evaluated amount large; tapping opens the keypad.
struct AmountField: View {
    let draft: ExpenseDraft
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if let total = draft.total {
                    AmountText(money: total, font: AppFont.title)
                } else {
                    Text("Amount")
                        .font(AppFont.title)
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Image(systemName: "keyboard")
                    .foregroundStyle(Color.inkMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Amount"))
        .accessibilityValue(Text(draft.total.map(SpokenAmount.text(for:)) ?? ""))
        .accessibilityHint(Text("Opens the keypad"))
    }
}
