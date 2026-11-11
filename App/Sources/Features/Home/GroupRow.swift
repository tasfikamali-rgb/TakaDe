import SwiftUI
import TakaDeCore

struct GroupRow: View {
    @Environment(AppModel.self) private var model
    let group: ExpenseGroup
    var isSelected = false
    @State private var net: Money = .zero()

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: group.name)
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                Text("\(group.members.count) people")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: Spacing.s)
            BalancePill(net: net)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isSelected ? Color.surfaceRaised : Color.surface)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: model.revision) { await loadNet() }
    }

    private func loadNet() async {
        guard let me = group.me, let balances = try? await model.balances(for: group) else { return }
        net = balances.net(for: me.id)
    }
}
