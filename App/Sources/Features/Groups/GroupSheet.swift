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
    let onAddFromContacts: () -> Void
    let onOpenMember: (Member) -> Void
    var onAddTakaDeUser: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SheetGrabber()
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(AppFont.label)
                    .foregroundStyle(Color.owe)
            }
            if let balances = model.balances {
                MemberBalancesCard(group: group, balances: balances, onAddMember: onAddMember, onAddFromContacts: onAddFromContacts, onOpenMember: onOpenMember,
                                   onAddTakaDeUser: onAddTakaDeUser)
            }
            if group.isMess {
                MealsCard(group: group)
            }
            ExpensesCard(group: group, expenses: model.expenses, onOpen: onOpen, onDelete: onDelete)
            if !model.settlements.isEmpty {
                PaymentsCard(group: group, settlements: model.settlements)
            }
            VStack(spacing: 0) {
                NavigationLink { HistoryView(group: group) } label: {
                    LinkRow(title: "History", systemImage: "clock", trailing: "chevron.right")
                }
                Divider().padding(.leading, Spacing.m)
                let export = SpreadsheetExport(group: group, expenses: model.expenses, settlements: model.settlements)
                ShareLink(item: export, preview: SharePreview(Text(verbatim: export.fileName))) {
                    LinkRow(title: "Export to spreadsheet", systemImage: "tablecells", trailing: "square.and.arrow.up")
                }
                .accessibilityHint(Text("Shares a CSV file of every expense and payment in this group"))
            }
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
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

/// A tappable row in the group's last card: icon, title, and a hint of what happens.
private struct LinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let trailing: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: trailing).foregroundStyle(Color.inkMuted).accessibilityHidden(true)
        }
        .font(AppFont.bodyEmphasis)
        .foregroundStyle(Color.ink)
        .padding(Spacing.m)
        .contentShape(Rectangle())
    }
}
