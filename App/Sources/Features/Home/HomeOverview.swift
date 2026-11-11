import SwiftUI
import TakaDeCore

/// The dark balance header with the groups sheet sliding over it.
struct HomeOverview: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: GroupID?
    let onNewGroup: () -> Void
    @State private var total: Money = .zero()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HomeHeader(total: total, onNewGroup: onNewGroup)
                GroupListSheet(groups: model.groups, selection: $selection, onNewGroup: onNewGroup)
            }
        }
        .background(alignment: .top) {
            Color.header.frame(height: 480).ignoresSafeArea()
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.revision) { total = await model.myTotal() }
    }
}
