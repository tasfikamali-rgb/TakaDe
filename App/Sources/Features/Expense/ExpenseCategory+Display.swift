import SwiftUI
import TakaDeCore

extension ExpenseCategory {
    var label: LocalizedStringKey {
        switch self {
        case .food: "Food"
        case .groceries: "Bazar"
        case .transport: "Transport"
        case .stay: "Stay"
        case .rent: "Rent"
        case .utilities: "Bills"
        case .shopping: "Shopping"
        case .fun: "Fun"
        case .health: "Health"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "basket"
        case .transport: "car"
        case .stay: "bed.double"
        case .rent: "house"
        case .utilities: "bolt"
        case .shopping: "bag"
        case .fun: "sparkles"
        case .health: "cross.case"
        case .other: "square.grid.2x2"
        }
    }
}

/// The category's icon in a soft circle, the same size as an avatar.
struct CategoryBadge: View {
    let category: ExpenseCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.surfaceRaised))
            .accessibilityHidden(true)
    }
}
