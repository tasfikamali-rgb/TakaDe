import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, activity, account, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Groups"
        case .activity: "Activity"
        case .account: "Account"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "person.3"
        case .activity: "list.bullet.rectangle"
        case .account: "person.crop.circle"
        case .settings: "gearshape"
        }
    }
}
