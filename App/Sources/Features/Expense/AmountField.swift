import SwiftUI
import TakaDeCore

/// Shows the evaluated amount large; tapping opens the keypad.
struct AmountField: View {
    let draft: ExpenseDraft
    var size: AmountSize = .title
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if let total = draft.total {
                    AmountText(money: total, size: size, color: .ink, minorColor: .inkMuted)
                } else {
                    Text("Amount")
                        .font(AppFont.display(size.points, relativeTo: .title))
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Image(systemName: "keyboard")
                    .foregroundStyle(Color.ink.opacity(0.72))
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
