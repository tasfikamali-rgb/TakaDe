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
                Text(describe(event)).font(AppFont.body)
                Text(event.occurredAt, format: .dateTime.day().month().hour().minute())
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .navigationTitle("History")
        .task { events = (try? await model.repository.history(of: group.id)) ?? [] }
    }

    private func describe(_ e: AuditEvent) -> String {
        let who = e.actor.map { group.member($0)?.isMe == true ? String(localized: "You") : group.name(of: $0) } ?? String(localized: "Someone")
        switch (e.entity, e.action) {
        case (.group, .created): return String(localized: "\(who) created the group")
        case (.group, _): return String(localized: "\(who) changed the group")
        case (.expense, .created): return String(localized: "\(who) added an expense")
        case (.expense, .edited): return String(localized: "\(who) edited an expense")
        case (.expense, .deleted): return String(localized: "\(who) deleted an expense")
        case (.settlement, _): return String(localized: "\(who) recorded a payment")
        default: return String(localized: "\(who) made a change")
        }
    }
}
