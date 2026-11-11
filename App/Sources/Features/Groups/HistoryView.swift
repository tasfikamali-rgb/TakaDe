import SwiftUI
import TakaDeCore

/// Append-only change log for a group.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    let group: ExpenseGroup
    @State private var events: [AuditEvent] = []

    var body: some View {
        List(events) { event in
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: HistoryDescription.text(for: event, in: group)).font(AppFont.body)
                Text(event.occurredAt, format: .dateTime.day().month().hour().minute())
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .overlay {
            if events.isEmpty { ContentUnavailableView("No changes yet", systemImage: "clock") }
        }
        .readableWidth()
        .navigationTitle("History")
        .task(id: model.revision) { events = (try? await model.repository.history(of: group.id)) ?? [] }
    }
}
