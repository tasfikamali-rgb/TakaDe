import SwiftUI

@main
struct TakaDeApp: App {
    @State private var model = AppModel.live()
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, language.locale ?? .autoupdatingCurrent)
                .task { await model.reload() }
        }
    }
}
