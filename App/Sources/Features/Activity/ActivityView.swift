import SwiftUI
import TakaDeCore

/// Recent expenses across all groups.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [ActivityItem] = []

    var body: some View {
        List(items) { item in
            ActivityRow(item: item)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle", description: Text("Expenses you add in any group show up here"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .readableWidth()
        .navigationTitle("Activity")
        .task(id: model.revision) { items = await model.recentActivity() }
    }
}
