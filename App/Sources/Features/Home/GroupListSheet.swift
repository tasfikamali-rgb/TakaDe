import SwiftUI
import TakaDeCore

/// The light sheet with a grabber and large rounded top corners that overlaps the dark
/// header, so header and content read as two physical layers.
struct GroupListSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(GroupSync.self) private var sync
    let groups: [ExpenseGroup]
    @Binding var selection: GroupID?
    let onNewGroup: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SheetGrabber()
                .padding(.bottom, Spacing.xs)
            HStack(alignment: .firstTextBaseline) {
                Text("Groups")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if sync.isAvailable && !groups.isEmpty {
                    Button("Join with a link", systemImage: "link", action: onJoin)
                        .font(AppFont.label)
                        .foregroundStyle(Color.ink)
                        .frame(minHeight: 44)
                }
            }
            .padding(.bottom, Spacing.xxs)
            if groups.isEmpty {
                EmptyGroupsCard(onNewGroup: onNewGroup, onJoin: sync.isAvailable ? onJoin : nil)
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
            TexturedBackground()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous))
                // Cream header over a lighter cream sheet is a small step, so lift the sheet edge in light mode.
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 12, y: -4)
        )
        .offset(y: -Radius.sheet)
        .padding(.bottom, -Radius.sheet)
    }
}
