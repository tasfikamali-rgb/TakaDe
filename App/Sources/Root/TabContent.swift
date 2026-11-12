import SwiftUI

struct TabContent: View {
    @Environment(AppChrome.self) private var chrome
    let tab: AppTab

    var body: some View {
        content
            // Room for the floating pill bar, so the last row and pinned buttons stay reachable.
            .safeAreaPadding(.bottom, reservesBar ? PillTabBar.reservedHeight : 0)
    }

    private var reservesBar: Bool { chrome.showsPillBar && !chrome.hidesTabBar }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: HomeView()
        case .activity: NavigationStack { ActivityView() }
        case .account: NavigationStack { AccountView() }
        }
    }
}
