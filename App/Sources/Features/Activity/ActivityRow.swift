import SwiftUI
import TakaDeCore

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: item.expense.title).font(AppFont.body)
                Text("\(item.group.name) · \(item.expense.occurredAt.formatted(.dateTime.day().month()))")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            AmountText(money: item.expense.total, font: AppFont.bodyEmphasis)
        }
        .accessibilityElement(children: .combine)
    }
}
