import SwiftUI
import TakaDeCore

/// The balance header (near-white in light mode, dark gray in dark) with the groups sheet sliding over it.
struct HomeOverview: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: GroupID?
    let onNewGroup: () -> Void
    let onJoin: () -> Void
    @State private var total: Money = .zero()
    @State private var showingGroupPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HomeHeader(total: total, hasGroups: !model.groups.isEmpty, onAddExpense: addExpense, onNewGroup: onNewGroup)
                GroupListSheet(groups: model.groups, selection: $selection, onNewGroup: onNewGroup, onJoin: onJoin)
            }
        }
        .background(alignment: .top) {
            TexturedBackground(base: .header).frame(height: 480).ignoresSafeArea()
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingGroupPicker) { GroupPickerSheet(groups: model.groups) }
        .task(id: model.revision) { total = await model.myTotal() }
    }

    private func addExpense() { showingGroupPicker = true }
}
