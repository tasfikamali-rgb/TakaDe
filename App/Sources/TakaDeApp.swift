import SwiftUI

@main
struct TakaDeApp: App {
    @State private var model: AppModel
    @State private var account: AccountModel
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

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
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                .task {
                    await account.load()
                    await model.reload()
                }
        }
    }
}
