import Foundation
import TakaDeCore

enum HistoryDescription {
    static func text(for e: AuditEvent, in group: ExpenseGroup) -> String {
        let who = e.actor.map(group.displayName(of:)) ?? String(localized: "Someone")
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
