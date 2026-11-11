import SwiftUI

struct EmptyGroupsCard: View {
    let onNewGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("No groups yet")
                .font(AppFont.bodyEmphasis)
            Text("Make one for a trip, a flat or a dinner, then add what each person paid. Everything stays on this phone.")
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
            Button("Create a group", action: onNewGroup)
                .buttonStyle(PillButtonStyle())
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
    }
}
