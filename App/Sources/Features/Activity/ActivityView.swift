import SwiftUI
import TakaDeCore

/// What happened across all groups: expenses and payments added, edited or deleted, and
/// who did it. Edits list what changed, like "Amount: ৳ 500.00 → ৳ 650.00".
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var items: [ActivityItem] = []

    var body: some View {
        List(items) { item in
            ActivityRow(item: item)
                .listRowBackground(Color.surface)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Expenses, payments and edits in any group show up here"))
            }
        }
        .texturedBackground()
        .readableWidth()
        .navigationTitle("Activity")
        .task(id: TaskKey(revision: model.revision, locale: locale.identifier)) { items = await model.recentActivity(locale: locale) }
    }

    private struct TaskKey: Hashable {
        let revision: Int
        let locale: String
    }
}
