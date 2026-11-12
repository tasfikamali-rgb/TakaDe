import SwiftUI
import TakaDeCore

/// "Add expense" from Home: pick the group first (skipped when there's only one).
struct GroupPickerSheet: View {
    let groups: [ExpenseGroup]
    @State private var chosen: ExpenseGroup?

    var body: some View {
        if let group = chosen ?? (groups.count == 1 ? groups.first : nil) {
            AddExpenseView(group: group)
        } else {
            NavigationStack {
                List(groups) { group in
                    Button { chosen = group } label: {
                        HStack(spacing: Spacing.s) {
                            AvatarStack(names: group.members.map(\.displayName), size: 24)
                            Text(verbatim: group.name).foregroundStyle(Color.ink)
                        }
                    }
                    .listRowBackground(Color.surface)
                }
                .texturedBackground()
                .navigationTitle("Which group?")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}
