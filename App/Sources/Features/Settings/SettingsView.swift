import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic

    var body: some View {
        AppForm {
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
            Section {
                NavigationLink {
                    DataAndExportView()
                } label: {
                    Label("Data and export", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.ink)
                }
            } footer: {
                Text("What's stored where, and a copy of all your groups.")
                    .foregroundStyle(Color.inkMuted)
            }
            DeleteSection()
        }
        .readableWidth()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings > Data and export: what's stored where, export everything, delete everything.
struct DataAndExportView: View {
    var body: some View {
        AppForm { YourDataSection() }
            .readableWidth()
            .navigationTitle("Data and export")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let app = AppModel.preview()
    return NavigationStack { SettingsView() }
        .environment(app)
        .environment(AccountModel(store: app.profiles, google: nil))
        .environment(AppLock())
}
