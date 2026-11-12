import SwiftUI
import TakaDeCore

struct PaymentsCard: View {
    @Environment(AppModel.self) private var app
    let group: ExpenseGroup
    let settlements: [Settlement]
    let onEdit: (Settlement) -> Void
    @State private var confirmError: String?

    var body: some View {
        SectionCard(title: "Payments") {
            ForEach(settlements) { settlement in
                VStack(alignment: .leading, spacing: 0) {
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
                    if settlement.awaitsMyConfirmation(in: group) {
                        Button { Task { await confirmReceived(settlement) } } label: {
                            Label("I got it", systemImage: "checkmark.circle")
                                .font(AppFont.label)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.ink)
                        .padding(.bottom, Spacing.xs)
                        .accessibilityHint(Text("Marks this payment received. Only do this once the money has reached you."))
                    }
                }
            }
            if let confirmError {
                Text(verbatim: confirmError)
                    .font(AppFont.label)
                    .foregroundStyle(Color.owe)
            }
        }
    }

    /// The person paid confirms the money arrived. This is their word, not a check with bKash.
    private func confirmReceived(_ settlement: Settlement) async {
        guard let me = group.me else { return }
        var received = settlement
        do {
            try received.acknowledge(by: me.id)
            try await app.record(received, in: group)
            confirmError = nil
        } catch {
            confirmError = String(localized: "The payment wasn't marked received. Try again.", bundle: .appLanguage)
        }
    }
}

extension Settlement {
    /// Reversed and provider-confirmed payments are closed; anything else can be fixed.
    var isEditable: Bool { status != .reversed && status != .confirmed }

    /// Someone recorded paying me and I haven't said I got it yet.
    func awaitsMyConfirmation(in group: ExpenseGroup) -> Bool {
        guard let me = group.me else { return false }
        return to == me.id && from != me.id && status == .reportedUnverified
    }
}
