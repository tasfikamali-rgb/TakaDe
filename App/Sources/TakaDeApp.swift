import BackgroundTasks
import SwiftUI
import TakaDeCore
import UserNotifications

@main
struct TakaDeApp: App {
    @State private var model: AppModel
    @State private var account: AccountModel
    @State private var sync: GroupSync
    @State private var friends: Friends
    @State private var social: SocialModel
    @State private var lock = AppLock()
    @State private var notifications: GroupNotifications
    /// Shown on every open: a cold launch and each return from the background (Sabit,
    /// 2026-11-11). Not after Control Center or a notification pull, which only pass
    /// through .inactive. A new `splashRun` restarts the animation; see LaunchSplash.
    @State private var showsSplash = true
    @State private var splashRun = 0
    @State private var wasInBackground = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        let account = AccountModel(store: model.profiles)
        let sync = GroupSync(app: model)
        _account = State(initialValue: account)
        _sync = State(initialValue: sync)
        let friends = Friends(account: account, sync: sync)
        _friends = State(initialValue: friends)
        _social = State(initialValue: SocialModel(store: model.social, account: account, friends: friends))
        // Set before launch finishes, so tapping a notification that opened the app is handled.
        let notifications = GroupNotifications()
        UNUserNotificationCenter.current().delegate = notifications
        sync.onChangesFromOthers = { [weak notifications] group, changes in
            await notifications?.changesArrived(changes, in: group, app: model)
        }
        _notifications = State(initialValue: notifications)
        // Switches take the app tint (ink), which is near-white in dark mode: a white knob
        // on a white track, so on and off looked alike. Lime "on" reads in both modes.
        UISwitch.appearance().onTintColor = UIColor(named: "toggleOn")
    }

    var body: some Scene {
        // Captured once for the background refresh below, which runs without any window.
        let sync = sync
        WindowGroup {
            // No .id(language) here: rebuilding the whole window closed and reopened the
            // onboarding cover on every language tap, flashing the app behind it and losing
            // the step. RootView rebuilds only its content on a language change instead.
            RootView()
                .environment(model)
                .environment(account)
                .environment(lock)
                .environment(sync)
                .environment(friends)
                .environment(social)
                .environment(notifications)
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                .task {
                    await account.load()
                    await model.reload()
                    await model.addDueRepeats()
                    await sync.syncAll()
                    await friends.checkInbox()
                    await social.start()
                }
                // Invite links: takade://join?… now, https://takadeapp.com/join?… later.
                .onOpenURL { url in
                    if let invite = GroupInvite(url: url) { sync.pendingInvite = PendingInvite(invite: invite) }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lock.scenePhaseChanged(to: phase)
                    if phase == .background {
                        wasInBackground = true
                        // Messages wait on the server until the app is back.
                        social.stop()
                        Self.scheduleRefresh()
                    }
                    if phase == .active, wasInBackground {
                        wasInBackground = false
                        splashRun += 1
                        showsSplash = true
                    }
                    // Windows can appear after launch (a new scene, the lock cover).
                    if phase == .active {
                        appearance.apply(animated: false)
                        // Rent due today shows up when the app comes back, not only at launch.
                        Task {
                            await model.addDueRepeats()
                            await sync.syncAll()
                            await friends.checkInbox()
                            await social.start()
                        }
                    }
                }
                .onChange(of: appearance, initial: true) { old, new in
                    new.apply(animated: old != new)
                }
                .overlay {
                    if showsSplash {
                        LaunchSplash { showsSplash = false }
                            .id(splashRun)
                    }
                }
        }
        // While TakaDe is closed, iOS wakes it now and then to pull shared groups' changes,
        // which is when group notifications can arrive without push. iOS picks the times.
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            Self.scheduleRefresh()
            await sync.syncAll()
        }
    }

    /// Also in Info.plist under BGTaskSchedulerPermittedIdentifiers.
    nonisolated static let refreshTaskID = "app.takade.refresh"

    /// Asks iOS for a background refresh in about 15 minutes or later. Only shared groups
    /// are synced in it, so there's nothing to do for someone who shares nothing.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
