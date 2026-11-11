import SwiftUI
import TakaDeCore

/// The content sheet of a group screen.
struct GroupSheet: View {
    let group: ExpenseGroup
    let model: GroupDetailModel
    let errorMessage: String?
    let onOpen: (Expense) -> Void
    let onDelete: (Expense) -> Void
    let onAddMember: () -> Void
    let onOpenMember: (Member) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SheetGrabber()
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(AppFont.label)
                    .foregroundStyle(Color.owe)
            }
            if let balances = model.balances {
                MemberBalancesCard(group: group, balances: balances, onAddMember: onAddMember, onOpenMember: onOpenMember)
            }
            if group.isMess {
                MealsCard(group: group)
            }
            ExpensesCard(group: group, expenses: model.expenses, onOpen: onOpen, onDelete: onDelete)
            if !model.settlements.isEmpty {
                PaymentsCard(group: group, settlements: model.settlements)
            }
            NavigationLink { HistoryView(group: group) } label: {
                HStack {
                    Label("History", systemImage: "clock")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted).accessibilityHidden(true)
                }
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.ink)
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.huge * 2)
        .readableWidth()
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                .fill(Color.canvas)
        )
        .offset(y: -Radius.sheet)
        .padding(.bottom, -Radius.sheet)
    }
}
