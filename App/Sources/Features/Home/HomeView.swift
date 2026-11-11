import SwiftUI
import TakaDeCore

/// Home: one job, show where I stand overall, then my groups.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var total: Money = .zero()
    @State private var showingNewGroup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Groups")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.ink)
                    if model.groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.groups) { group in
                            NavigationLink(value: group.id) {
                                GroupRow(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                        .fill(Color.canvas)
                        .ignoresSafeArea(edges: .bottom)
                )
                .offset(y: -Radius.sheet)
                .padding(.bottom, -Radius.sheet)
            }
        }
        .background(alignment: .top) { Color.header.frame(height: 400).ignoresSafeArea() }
        .background(Color.canvas)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: GroupID.self) { id in
            if let group = model.groups.first(where: { $0.id == id }) {
                GroupDetailView(groupID: group.id)
            }
        }
        .sheet(isPresented: $showingNewGroup) { NewGroupView() }
        .task(id: model.groups) { total = await model.myTotal() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(total.minorUnits >= 0 ? LocalizedStringKey("You are owed in total") : LocalizedStringKey("You owe in total"))
                .font(AppFont.label)
                .foregroundStyle(Color.onHeader.opacity(0.7))
            AmountText(money: total.magnitude, color: .onHeader)
            Button {
                showingNewGroup = true
            } label: {
                Text("New group")
                    .font(AppFont.label)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
                    .background(Capsule().fill(Color.onHeader))
                    .foregroundStyle(Color.header)
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.huge + Radius.sheet)
        .background(Color.header)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No groups yet")
                .font(AppFont.body.weight(.semibold))
            Text("Create a group for a trip, a flat or a dinner, then add what each person paid.")
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
    }
}

private struct GroupRow: View {
    @Environment(AppModel.self) private var model
    let group: ExpenseGroup
    @State private var net: Money = .zero()

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(group.name)
                    .font(AppFont.body.weight(.semibold))
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
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
        .contentShape(Rectangle())
        .task(id: group) {
            if let me = group.me, let balances = try? await model.balances(for: group) {
                net = balances.net(for: me.id)
            }
        }
    }
}
