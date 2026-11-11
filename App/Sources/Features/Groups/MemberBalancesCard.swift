import SwiftUI
import TakaDeCore

struct MemberBalancesCard: View {
    let group: ExpenseGroup
    let balances: GroupBalances
    let onAddMember: () -> Void
    let onAddFromContacts: () -> Void
    /// Opens the person's bKash, Nagad, Rocket, upay or bank numbers.
    let onOpenMember: (Member) -> Void

    var body: some View {
        SectionCard(title: "Balances") {
            Menu {
                Button("Type a name", systemImage: "character.cursor.ibeam", action: onAddMember)
                Button("Choose from Contacts", systemImage: "person.crop.circle", action: onAddFromContacts)
            } label: {
                Label("Add a person", systemImage: "person.badge.plus")
            }
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.ink)
                .frame(minWidth: 44, minHeight: 44)
        } content: {
            ForEach(group.members) { member in
                Button { onOpenMember(member) } label: {
                    HStack(spacing: Spacing.s) {
                        Avatar(name: member.displayName, size: 36)
                        Text(verbatim: group.displayName(of: member.id))
                            .font(AppFont.body)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        BalancePill(net: balances.net(for: member.id), isMe: member.isMe)
                    }
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows their bKash and bank numbers"))
            }
            if let me = group.me, let unverified = balances.unverifiedSettled[me.id], !unverified.isZero {
                HStack(spacing: Spacing.xxs) {
                    Text("Includes payments you recorded that no provider has verified:")
                    AmountText(money: unverified, size: .caption, color: .inkMuted)
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
