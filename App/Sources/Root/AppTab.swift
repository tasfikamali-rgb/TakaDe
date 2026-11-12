import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, social, activity, account

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Groups"
        case .social: "Social"
        case .activity: "Activity"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "person.2"
        case .social: "bubble.left.and.bubble.right"
        case .activity: "arrow.left.arrow.right"
        case .account: "person.crop.circle"
        }
    }
}
