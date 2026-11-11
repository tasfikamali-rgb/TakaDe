import SwiftUI
import TakaDeCore

/// The lilac header of Settle up: who pays whom and how much, large, with the reminder
/// that TakaDe only records payments made elsewhere.
struct SettleUpHeader: View {
    let group: ExpenseGroup
    let transfer: SuggestedTransfer?
    /// True when there's nothing for you to pay or receive in this group.
    let isSettled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let transfer {
                Text(verbatim: describe(transfer))
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink.opacity(0.72))
                AmountText(money: transfer.amount, size: .balance, color: .ink, minorColor: .ink.opacity(0.6))
            } else {
                Text(isSettled ? LocalizedStringKey("You're settled up in this group") : LocalizedStringKey("Pick a payment below"))
                    .font(AppFont.title)
                    .foregroundStyle(Color.ink)
            }
            Text("TakaDe doesn't send money. Pay with cash, bKash or your bank as usual, then record it here.")
                .font(AppFont.caption)
                .foregroundStyle(Color.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.xxs)
        }
        .accessibilityElement(children: .combine)
    }

    private func describe(_ t: SuggestedTransfer) -> String {
        t.from == group.me?.id
            ? String(localized: "You pay \(group.storedName(of: t.to))", bundle: .appLanguage)
            : String(localized: "\(group.storedName(of: t.from)) pays you", bundle: .appLanguage)
    }
}
