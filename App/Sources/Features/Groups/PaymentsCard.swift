import SwiftUI
import TakaDeCore

struct PaymentsCard: View {
    let group: ExpenseGroup
    let settlements: [Settlement]

    var body: some View {
        SectionCard(title: "Payments") {
            ForEach(settlements) { settlement in
                SettlementRow(settlement: settlement, group: group)
                    .padding(.vertical, Spacing.xs)
            }
        }
    }
}
