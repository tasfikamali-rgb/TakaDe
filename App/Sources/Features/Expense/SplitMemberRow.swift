import SwiftUI
import TakaDeCore

struct SplitMemberRow: View {
    @Bindable var draft: ExpenseDraft
    let member: Member

    var body: some View {
        HStack {
            switch draft.method {
            case .equal:
                Toggle(isOn: $draft[includes: member.id]) { Text(verbatim: name) }
            case .exact:
                Text(verbatim: name)
                Spacer()
                TextField("0", text: $draft[exactFor: member.id])
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 120)
                    .accessibilityLabel(Text("Amount for \(name)"))
            case .percentage:
                Text(verbatim: name)
                Spacer()
                TextField("0", text: $draft[percentFor: member.id])
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 72)
                    .accessibilityLabel(Text("Percent for \(name)"))
                Text(verbatim: "%").foregroundStyle(Color.inkMuted)
            case .shares:
                Stepper(value: $draft[sharesFor: member.id], in: 0...99) {
                    Text("\(name) · ^[\(draft[sharesFor: member.id]) share](inflect: true)")
                }
            }
            if draft.method != .exact, let share = draft.share(for: member.id), !share.isZero {
                AmountText(money: share, size: .label, color: .inkMuted)
                    .frame(minWidth: 72, alignment: .trailing)
            }
        }
    }

    private var name: String { draft.group.displayName(of: member.id) }
}
