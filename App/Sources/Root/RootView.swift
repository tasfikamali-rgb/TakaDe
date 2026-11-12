import SwiftUI

/// On a tall compact window (an iPhone held upright) the floating pill bar from DESIGN.md
/// replaces the system tab bar. Everywhere else (iPad, iPhone Duo's displays, landscape,
/// wide windows) the system tab bar returns so the platform can place and adapt it.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @Environment(GroupSync.self) private var sync
    @Environment(Friends.self) private var friends
    @Environment(SocialModel.self) private var social
    @Environment(GroupNotifications.self) private var notifications
    @Environment(ActivityInbox.self) private var inbox
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Scene storage, so a language switch (which rebuilds the tabs) or a new window
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

    private func unread(_ tab: AppTab) -> Int {
        switch tab {
        case .social: social.unreadTotal
        case .activity: inbox.unread
        default: 0
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { item in
                TabContent(tab: item)
                    .tabItem { Label(item.title, systemImage: item.systemImage) }
                    .badge(unread(item))
                    .tag(item)
                    .toolbar(usesPillBar ? .hidden : .automatic, for: .tabBar)
            }
        }
        .tint(.ink)
        .toggleStyle(AppSwitchStyle())
        // Fonts and strings are fixed when built, so rebuild the tabs on a text size or
        // language change. Only the tabs: the onboarding cover and invite sheet below hang off
        // this view and must not close and reopen when the language changes.
        .rebuildsOnDynamicType()
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
            // `-auditHideTabBar YES` is a UI-test switch for telling tab-bar audit issues apart.
            if usesPillBar && !chrome.hidesTabBar && !UserDefaults.standard.bool(forKey: "auditHideTabBar") {
                PillTabBar(selection: $tab, unread: [.social: social.unreadTotal, .activity: inbox.unread])
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
        // Activity on screen: what arrives counts as seen, and opening it clears the number.
        .onChange(of: tab == .activity && scenePhase == .active, initial: true) { _, viewing in
            inbox.isViewing = viewing
        }
        // While the app is open, check shared groups once a minute, so other people's
        // changes reach Activity and its number without a pull. One small request per shared
        // group; no live connection (Realtime is kept for open chats, PR #47).
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await sync.syncAll()
            }
        }
        .environment(chrome)
        .googlePhotoOffer(when: !account.needsOnboarding)
        // A new or removed profile photo goes, sealed, to friends so their phones show it.
        .onChange(of: account.photoRevision) { Task { await social.shareProfile() } }
        // After "Delete all my data" the app starts over like a first launch: on Groups,
        // not on the tab (Account > Settings) that was open when the data was deleted.
        .onChange(of: account.needsOnboarding) { _, needsOnboarding in
            if needsOnboarding { tab = .home }
        }
        .fullScreenCover(isPresented: Binding(get: { account.needsOnboarding }, set: { _ in })) {
            OnboardingView().rebuildsOnDynamicType()
        }
        // A tapped invite link. Waits until onboarding is done for someone new to TakaDe.
        // Next, any other invite friends sent by TakaDe ID.
        .sheet(item: Binding(get: { account.needsOnboarding ? nil : sync.pendingInvite }, set: { sync.pendingInvite = $0 }),
               onDismiss: { Task { await friends.offerClosed() } }) { pending in
            JoinGroupSheet(invite: pending.invite, from: pending.from) { id in
                tab = .home
                model.requestedGroup = id
            }
            .rebuildsOnDynamicType()
        }
        // A tapped group notification opens that group.
        .onChange(of: notifications.tappedGroup, initial: true) { _, id in
            guard let id else { return }
            tab = .home
            model.requestedGroup = id
            notifications.tappedGroup = nil
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
    let account = AccountModel(store: app.profiles, google: nil)
    let sync = GroupSync(app: app, config: nil)
    let friends = Friends(account: account, sync: sync)
    return RootView().environment(app).environment(account)
        .environment(sync)
        .environment(friends)
        .environment(GroupNotifications())
        .environment(ActivityInbox())
        .environment(SocialModel(store: app.social, account: account, friends: friends))
}
