import SwiftUI
import TakaDeCore

struct TransferPickerSection: View {
    let group: ExpenseGroup
    let transfers: [SuggestedTransfer]
    @Binding var selected: SuggestedTransfer?

    var body: some View {
        Section("Suggested payments") {
            if transfers.isEmpty {
                Text("You're settled up in this group")
            }
            ForEach(transfers, id: \.self) { transfer in
                Button { selected = transfer } label: {
                    HStack {
                        Text(verbatim: describe(transfer))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        AmountText(money: transfer.amount, font: AppFont.bodyEmphasis)
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.ink)
                            .opacity(selected == transfer ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(selected == transfer ? .isSelected : [])
            }
        }
    }

    private func describe(_ t: SuggestedTransfer) -> String {
        t.from == group.me?.id
            ? String(localized: "You pay \(group.storedName(of: t.to))")
            : String(localized: "\(group.storedName(of: t.from)) pays you")
    }
}
