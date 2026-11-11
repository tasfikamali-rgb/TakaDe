import SwiftUI

/// On compact width (iPhone, a folded phone, narrow split view) the floating notch bar
/// from DESIGN.md replaces the system tab bar. On regular width (iPad, wide windows,
/// an unfolded phone) the system tab bar returns so the platform can adapt it.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tab: AppTab = .home

    private var usesNotchBar: Bool { horizontalSizeClass != .regular }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { item in
                TabContent(tab: item)
                    .tabItem { Label(item.title, systemImage: item.systemImage) }
                    .tag(item)
                    .toolbar(usesNotchBar ? .hidden : .automatic, for: .tabBar)
            }
        }
        .tint(.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesNotchBar {
                NotchTabBar(selection: $tab)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xs)
            }
        }
        .overlay(alignment: .top) {
            if let error = model.loadError {
                ErrorBanner(message: error)
            }
        }
    }
}

#Preview {
    RootView().environment(AppModel.preview())
}
