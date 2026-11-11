import SwiftUI

/// On compact width (iPhone, a folded phone, narrow split view) the floating notch bar
/// from DESIGN.md replaces the system tab bar. On regular width (iPad, wide windows,
/// an unfolded phone) the system tab bar returns so the platform can adapt it.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .home
    @State private var chrome = AppChrome()

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
        // A TabView doesn't pass a safe area inset down to its pages, so the bar floats in an
        // overlay and each page reserves room for it (TabContent).
        .overlay(alignment: .bottom) {
            if usesNotchBar && !chrome.hidesTabBar {
                NotchTabBar(selection: $tab)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xs)
                    .background(alignment: .bottom) {
                        // Content scrolls under the bar and fades out instead of being cut off.
                        LinearGradient(colors: [Color.canvas.opacity(0), Color.canvas], startPoint: .top, endPoint: .bottom)
                            .frame(height: NotchTabBar.reservedHeight + Spacing.xl)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea(.keyboard)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: chrome.hidesTabBar)
        .environment(chrome)
        .fullScreenCover(isPresented: Binding(get: { account.needsOnboarding }, set: { _ in })) {
            OnboardingView()
        }
        .overlay(alignment: .top) {
            if let error = model.loadError {
                ErrorBanner(message: error)
            }
        }
    }
}

#Preview {
    let app = AppModel.preview()
    return RootView().environment(app).environment(AccountModel(store: app.profiles, google: nil))
}
