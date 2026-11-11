import SwiftUI
import TakaDeCore

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: item.group.name, size: 36)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: item.expense.title).font(AppFont.bodyEmphasis)
                HStack(spacing: Spacing.xxs) {
                    Text(verbatim: item.group.name)
                    Text(verbatim: "·")
                    Text(item.expense.occurredAt, format: .dateTime.day().month())
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                if let share = myShare {
                    AmountText(money: share, size: .headline)
                    Text("your share")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                } else {
                    AmountText(money: item.expense.total, size: .headline)
                    Text("total")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var myShare: Money? {
        guard let me = item.group.me else { return nil }
        return item.expense.allocation.shares[me.id]
    }
}
