import SwiftUI
import TakaDeCore

struct PaymentsSection: View {
    let group: ExpenseGroup
    let settlements: [Settlement]

    var body: some View {
        Section("Payments") {
            ForEach(settlements) { settlement in
                SettlementRow(settlement: settlement, group: group)
            }
        }
    }
}
