import SwiftUI

/// The three ways to split in the form (Sabit asked for three, 2026-11-12). Equally covers
/// most bills, and leaving someone out is a toggle. Amounts covers "I had the biryani, you
/// had tea". Shares covers a couple counting as two, and any ratio such as 60/40 (3 and 2
/// shares), so percentages aren't needed. Older expenses split by percent or with extras
/// still count; they open as Amounts. See docs/adr/0022-edits-and-three-splits.md.
enum SplitMethod: String, CaseIterable, Identifiable {
    case equal, exact, shares

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .equal: "Equally"
        case .exact: "Amounts"
        case .shares: "Shares"
        }
    }
}
