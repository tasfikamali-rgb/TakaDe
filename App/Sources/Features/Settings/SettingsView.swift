import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language.choice) {
                    ForEach(AppLanguage.choices) { option in
                        Text(verbatim: option.nativeName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Language")
                    .foregroundStyle(Color.inkMuted)
            }
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Appearance")
                    .foregroundStyle(Color.inkMuted)
            }
            AppLockSection()
        }
        .readableWidth()
        .navigationTitle("Settings")
    }
}

#Preview {
    let app = AppModel.preview()
    return NavigationStack { SettingsView() }
        .environment(app)
        .environment(AccountModel(store: app.profiles, google: nil))
        .environment(AppLock())
}
