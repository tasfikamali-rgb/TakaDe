import SwiftUI
import TakaDeCore

/// Who paid: one person (the usual case), or several, each with what they paid.
/// The payer doesn't have to be in the split; that's set below.
struct PaidBySection: View {
    @Bindable var draft: ExpenseDraft

    var body: some View {
        Section {
            if draft.severalPayers {
                ForEach(draft.group.members) { member in
                    let name = draft.group.displayName(of: member.id)
                    HStack {
                        Text(verbatim: name)
                        Spacer()
                        TextField("0", text: $draft[paidFor: member.id])
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 120)
                            .accessibilityLabel(Text("Paid by \(name)"))
                    }
                }
            } else {
                Picker("Paid by", selection: $draft.payer) {
                    ForEach(draft.group.members) { member in
                        Text(verbatim: draft.group.displayName(of: member.id)).tag(member.id)
                    }
                }
            }
            Toggle("Several people paid", isOn: $draft.severalPayers)
        } footer: {
            if let unpaid = draft.unpaid {
                let amount = MoneyFormatter.format(unpaid.magnitude).plain
                if unpaid.isNegative {
                    Text("That's \(amount) more than the total").foregroundStyle(Color.owe)
                } else {
                    Text("\(amount) still to fill in").foregroundStyle(Color.inkMuted)
                }
            }
        }
    }
}
