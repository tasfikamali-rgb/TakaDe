import SwiftUI
import TakaDeCore

struct PaymentsCard: View {
    let group: ExpenseGroup
    let settlements: [Settlement]
    let onEdit: (Settlement) -> Void

    var body: some View {
        SectionCard(title: "Payments") {
            ForEach(settlements) { settlement in
                HStack(spacing: Spacing.xxs) {
                    if settlement.isEditable {
                        Button { onEdit(settlement) } label: {
                            SettlementRow(settlement: settlement, group: group)
                                .padding(.vertical, Spacing.xs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityHint(Text("Opens the payment to fix the amount, method or transaction ID"))
                        EditIconButton(label: Text("Edit payment")) { onEdit(settlement) }
                    } else {
                        SettlementRow(settlement: settlement, group: group)
                            .padding(.vertical, Spacing.xs)
                    }
                }
            }
        }
    }
}

extension Settlement {
    /// Reversed and provider-confirmed payments are closed; anything else can be fixed.
    var isEditable: Bool { status != .reversed && status != .confirmed }
}
