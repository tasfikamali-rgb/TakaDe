import SwiftUI
import TakaDeCore

/// Modelled on the savings-goal cards in DESIGN.md 1b: avatars and title, then a nested
/// inner card with where you stand on the left and what the group spent on the right.
/// Layering comes from two grays, not shadows. The arrow sits in a bite out of the top-right
/// corner (DESIGN.md 1b).
struct GroupCard: View {
    @Environment(AppModel.self) private var model
    let group: ExpenseGroup
    var isSelected = false
    @State private var stats = GroupStats.empty
    @State private var photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                GroupPhotoBadge(group: group, photo: photo, size: photo == nil ? 28 : 36, ring: isSelected ? .surfaceRaised : .surface)
                Text(verbatim: group.name)
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
            }
            // Keep the title clear of the corner icon.
            .padding(.trailing, CornerCutoutShape.biteSize - Spacing.s)
            .frame(minHeight: CornerCutoutShape.biteSize - Spacing.s)
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
        .background(CornerCutoutShape().fill(cardFill))
        .overlay(CornerCutoutShape().stroke(Color.ink, lineWidth: isSelected ? 2 : 0))
        .overlay(alignment: .topTrailing) {
            CornerCutoutIcon(systemImage: "arrow.up.right", fill: cardFill)
                .overlay(Circle().stroke(Color.ink, lineWidth: isSelected ? 2 : 0))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: model.revision) {
            photo = GroupPhotoFile.load(group.id)
            stats = await GroupStats.load(group, from: model)
        }
    }

    private var cardFill: Color { isSelected ? .surfaceRaised : .surface }
}
