import Foundation
import TakaDeCore

enum HistoryDescription {
    static func text(for e: AuditEvent, in group: ExpenseGroup) -> String {
        let who = e.actor.map(group.displayName(of:)) ?? String(localized: "Someone", bundle: .appLanguage)
        switch (e.entity, e.action) {
        case (.group, .created): return String(localized: "\(who) created the group", bundle: .appLanguage)
        case (.group, _): return String(localized: "\(who) changed the group", bundle: .appLanguage)
        case (.expense, .created): return String(localized: "\(who) added an expense", bundle: .appLanguage)
        case (.expense, .edited): return String(localized: "\(who) edited an expense", bundle: .appLanguage)
        case (.expense, .deleted): return String(localized: "\(who) deleted an expense", bundle: .appLanguage)
        case (.settlement, _): return String(localized: "\(who) recorded a payment", bundle: .appLanguage)
        case (.meal, _): return String(localized: "\(who) updated meal counts", bundle: .appLanguage)
        default: return String(localized: "\(who) made a change", bundle: .appLanguage)
        }
    }
}
