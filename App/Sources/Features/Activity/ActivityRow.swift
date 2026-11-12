import SwiftUI
import TakaDeCore

/// Who did what, in which group and when; for an edit, each change on its own line.
struct ActivityRow: View {
    let item: ActivityItem
    /// Activity mixes groups, so it names the group; a group's own History doesn't need to.
    var showsGroup = true

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            if showsGroup {
                GroupIconBadge(name: item.group.name, size: 36, fill: .surfaceRaised)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: item.headline).font(AppFont.bodyEmphasis)
                ForEach(item.details, id: \.self) { line in
                    Text(verbatim: line)
                        .font(AppFont.label)
                        .foregroundStyle(Color.ink)
                }
                HStack(spacing: Spacing.xxs) {
                    if showsGroup {
                        Text(verbatim: item.group.name)
                        Text(verbatim: "·")
                    }
                    Text(item.occurredAt, format: .dateTime.day().month().hour().minute())
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: Spacing.xs)
            if let amount = item.amount {
                AmountText(money: amount, size: .headline, color: item.isRemoved ? .inkMuted : .ink)
                    .strikethrough(item.isRemoved)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
