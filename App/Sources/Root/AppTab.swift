import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, activity, profile

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Groups"
        case .activity: "Activity"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "person.3"
        case .activity: "list.bullet.rectangle"
        case .profile: "person.crop.circle"
        }
    }
}
