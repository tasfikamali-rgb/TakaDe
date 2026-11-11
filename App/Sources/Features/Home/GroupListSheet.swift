import SwiftUI
import TakaDeCore

/// The light sheet with a grabber and large rounded top corners that overlaps the dark
/// header, so header and content read as two physical layers.
struct GroupListSheet: View {
    let groups: [ExpenseGroup]
    @Binding var selection: GroupID?
    let onNewGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SheetGrabber()
                .padding(.bottom, Spacing.xs)
            Text("Groups")
                .font(AppFont.headline)
                .foregroundStyle(Color.ink)
                .padding(.bottom, Spacing.xxs)
            if groups.isEmpty {
                EmptyGroupsCard(onNewGroup: onNewGroup)
            } else {
                ForEach(groups) { group in
                    Button { selection = group.id } label: {
                        GroupCard(group: group, isSelected: selection == group.id)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.huge * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableWidth()
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                .fill(Color.canvas)
        )
        .offset(y: -Radius.sheet)
        .padding(.bottom, -Radius.sheet)
    }
}
