import SwiftUI

struct TabContent: View {
    @Environment(AppChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let tab: AppTab

    var body: some View {
        content
            // Room for the floating notch bar, so the last row and pinned buttons stay reachable.
            .safeAreaPadding(.bottom, reservesBar ? NotchTabBar.reservedHeight : 0)
    }

    private var reservesBar: Bool { horizontalSizeClass != .regular && !chrome.hidesTabBar }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: HomeView()
        case .activity: NavigationStack { ActivityView() }
        case .profile: NavigationStack { SettingsView() }
        }
    }
}
