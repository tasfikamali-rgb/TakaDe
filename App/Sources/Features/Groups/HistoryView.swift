import SwiftUI
import TakaDeCore

/// Append-only change log for a group, with what each edit changed.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    let group: ExpenseGroup
    @State private var items: [ActivityItem] = []

    var body: some View {
        List(items) { item in
            ActivityRow(item: item, showsGroup: false)
        }
        .overlay {
            if items.isEmpty { ContentUnavailableView("No changes yet", systemImage: "clock") }
        }
        .readableWidth()
        .navigationTitle("History")
        .task(id: model.revision) {
            let events = (try? await model.repository.history(of: group.id)) ?? []
            items = ActivityFeed.items(for: events, in: group, locale: locale)
        }
    }
}
