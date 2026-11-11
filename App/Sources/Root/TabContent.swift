import SwiftUI

struct TabContent: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .home: HomeView()
        case .activity: NavigationStack { ActivityView() }
        case .profile: NavigationStack { SettingsView() }
        }
    }
}
