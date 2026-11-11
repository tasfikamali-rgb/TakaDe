import SwiftUI

struct EmptyGroupsCard: View {
    let onNewGroup: () -> Void
    /// Nil when this build can't join shared groups.
    var onJoin: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("No groups yet")
                .font(AppFont.bodyEmphasis)
            Text("Make one for a trip, a flat or a dinner, then add what each person paid. It stays on this phone unless you invite people.")
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
            Button("Create a group", action: onNewGroup)
                .buttonStyle(PillButtonStyle())
                .padding(.top, Spacing.xs)
            if let onJoin {
                Button("Join with a link", systemImage: "link", action: onJoin)
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
    }
}
