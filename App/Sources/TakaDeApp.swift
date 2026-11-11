import SwiftUI

@main
struct TakaDeApp: App {
    @State private var model: AppModel
    @State private var account: AccountModel
    @State private var lock = AppLock()
    /// Shown once per cold launch; see LaunchSplash.
    @State private var showsSplash = true
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic

    init() {
        let model = AppModel.live()
        _model = State(initialValue: model)
        _account = State(initialValue: AccountModel(store: model.profiles))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Rebuild the tree on a language change so every string re-resolves.
                .id(language)
                .environment(model)
                .environment(account)
                .environment(lock)
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                .task {
                    await account.load()
                    await model.reload()
                    await model.addDueRepeats()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lock.scenePhaseChanged(to: phase)
                    // Windows can appear after launch (a new scene, the lock cover).
                    if phase == .active {
                        appearance.apply(animated: false)
                        // Rent due today shows up when the app comes back, not only at launch.
                        Task { await model.addDueRepeats() }
                    }
                }
                .onChange(of: appearance, initial: true) { old, new in
                    new.apply(animated: old != new)
                }
                .overlay {
                    if showsSplash {
                        LaunchSplash { showsSplash = false }
                    }
                }
        }
    }
}
