import SwiftUI

enum SplitMethod: String, CaseIterable, Identifiable {
    case equal, exact, percentage, shares

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .equal: "Equally"
        case .exact: "Amounts"
        case .percentage: "Percent"
        case .shares: "Shares"
        }
    }
}
