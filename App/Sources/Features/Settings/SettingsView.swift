import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(DigitPreference.storageKey) private var digits: DigitPreference = .automatic
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    ForEach([AppLanguage.bengali, .english, .system]) { option in
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
            Section {
                Picker("Numbers", selection: $digits) {
                    Text("Automatic").tag(DigitPreference.automatic)
                    Text(verbatim: "123").tag(DigitPreference.latin)
                    Text(verbatim: "১২৩").tag(DigitPreference.bengali)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Numbers")
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
