import SwiftUI

@main
struct TakaDeApp: App {
    @State private var model = AppModel.live()
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                // Rebuild the tree on a language change so every string re-resolves.
                .id(language)
                .environment(model)
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                .task { await model.reload() }
        }
    }
}
