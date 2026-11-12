import SwiftUI

/// On a tall compact window (an iPhone held upright) the floating pill bar from DESIGN.md
/// replaces the system tab bar. Everywhere else (iPad, iPhone Duo's displays, landscape,
/// wide windows) the system tab bar returns so the platform can place and adapt it.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(GroupSync.self) private var sync
    @Environment(Friends.self) private var friends
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Scene storage, so a language switch (which rebuilds the whole tree) or a new window
    // comes back to the same tab instead of jumping to Groups.
    @SceneStorage("selectedTab") private var tab: AppTab = .home
    @State private var chrome = AppChrome()

    @State private var windowSize: CGSize = .zero

    /// The floating pill bar only fits a tall, narrow window: a phone held upright.
    /// Wider and shorter windows (iPhone Duo's outer display, landscape, the inner display)
    /// get the system tab bar, which the system moves to the side where that saves vertical
    /// space (HIG, Designing for iPhone Duo). Decided from the window, never the device model.
    private var usesPillBar: Bool {
        guard horizontalSizeClass != .regular else { return false }
        guard windowSize.width > 0 else { return true }
        return windowSize.height >= windowSize.width * 1.6
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { item in
                TabContent(tab: item)
                    .tabItem { Label(item.title, systemImage: item.systemImage) }
                    .tag(item)
                    .toolbar(usesPillBar ? .hidden : .automatic, for: .tabBar)
            }
        }
        .tint(.ink)
        // Fonts with a Bengali fallback are scaled when built, so rebuild on a text size change.
        .id(dynamicTypeSize)
        .onGeometryChange(for: CGSize.self) { proxy in
            // The whole window, safe areas included, so bars and notches don't skew the shape.
            let insets = proxy.safeAreaInsets
            return CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                          height: proxy.size.height + insets.top + insets.bottom)
        } action: { size in
            windowSize = size
            chrome.showsPillBar = usesPillBar
        }
        .onChange(of: horizontalSizeClass) { chrome.showsPillBar = usesPillBar }
        // A TabView doesn't pass a safe area inset down to its pages, so the bar floats in an
        // overlay and each page reserves room for it (TabContent).
        .overlay(alignment: .bottom) {
            if usesPillBar && !chrome.hidesTabBar {
                PillTabBar(selection: $tab)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xs)
                    .background(alignment: .bottom) {
                        // Content scrolls under the bar and fades out instead of being cut off.
                        LinearGradient(colors: [Color.canvas.opacity(0), Color.canvas], startPoint: .top, endPoint: .bottom)
                            .frame(height: PillTabBar.reservedHeight + Spacing.xl)
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
        // A tapped invite link. Waits until onboarding is done for someone new to TakaDe.
        // Next, any other invite friends sent by TakaDe ID.
        .sheet(item: Binding(get: { account.needsOnboarding ? nil : sync.pendingInvite }, set: { sync.pendingInvite = $0 }),
               onDismiss: { Task { await friends.checkInbox() } }) { pending in
            JoinGroupSheet(invite: pending.invite, from: pending.from) { id in
                tab = .home
                model.requestedGroup = id
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
    let app = AppModel.preview()
    return RootView().environment(app).environment(AccountModel(store: app.profiles, google: nil))
        .environment(GroupSync(app: app, config: nil))
        .environment(Friends(account: AccountModel(store: app.profiles, google: nil), sync: GroupSync(app: app, config: nil)))
}
