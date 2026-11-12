import SwiftUI
import TakaDeCore

@main
struct TakaDeApp: App {
    @State private var model: AppModel
    @State private var account: AccountModel
    @State private var sync: GroupSync
    @State private var lock = AppLock()
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
        _account = State(initialValue: AccountModel(store: model.profiles))
        _sync = State(initialValue: GroupSync(app: model))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Rebuild the tree on a language change so every string re-resolves.
                .id(language)
                .environment(model)
                .environment(account)
                .environment(lock)
                .environment(sync)
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                .task {
                    await account.load()
                    await model.reload()
                    await model.addDueRepeats()
                    await sync.syncAll()
                }
                // Invite links: takade://join?… now, https://takadeapp.com/join?… later.
                .onOpenURL { url in
                    if let invite = GroupInvite(url: url) { sync.pendingInvite = PendingInvite(invite: invite) }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lock.scenePhaseChanged(to: phase)
                    if phase == .background { wasInBackground = true }
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
    }
}
