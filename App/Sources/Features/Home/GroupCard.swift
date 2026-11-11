import SwiftUI
import TakaDeCore

/// Modelled on the savings-goal cards in DESIGN.md 1b: title and chevron, then a nested
/// inner card with where you stand on the left and what the group spent on the right.
/// Layering comes from two grays, not shadows.
struct GroupCard: View {
    @Environment(AppModel.self) private var model
    let group: ExpenseGroup
    var isSelected = false
    @State private var stats = GroupStats.empty

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                AvatarStack(names: group.members.map(\.displayName), size: 28, ring: isSelected ? .surfaceRaised : .surface)
                Text(verbatim: group.name)
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.inkMuted)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(BalanceState(stats.myNet).label)
                        .font(AppFont.caption)
                        .foregroundStyle(BalanceState(stats.myNet).color)
                    AmountText(money: stats.myNet.magnitude, size: .headline, color: BalanceState(stats.myNet).color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text("Spent together")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                    AmountText(money: stats.spent, size: .headline)
                }
            }
            .padding(Spacing.m)
            .background(RoundedRectangle(cornerRadius: Radius.card - Spacing.xs, style: .continuous).fill(Color.canvas))
            Text("\(group.members.count) people · ^[\(stats.expenseCount) expense](inflect: true)")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
        }
        .padding(Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isSelected ? Color.surfaceRaised : Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.ink, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: model.revision) { stats = await GroupStats.load(group, from: model) }
    }
}
