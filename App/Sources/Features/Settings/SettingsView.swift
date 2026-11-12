import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic
    @State private var showingData = false

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
                    .formHeader()
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
                    .formHeader()
            }
            NotificationsSection()
            AppLockSection()
            Section {
                // A button with its own chevron: the system NavigationLink chevron is drawn
                // in a faint grey that failed the accessibility audit's contrast check.
                Button { showingData = true } label: {
                    HStack {
                        Label("Data and export", systemImage: "square.and.arrow.up")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.inkMuted)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.ink)
                    .contentShape(Rectangle())
                }
            } footer: {
                Text("What's stored where, and a copy of all your groups.")
                    .foregroundStyle(Color.inkMuted)
            }
            DeleteSection()
        }
        .navigationDestination(isPresented: $showingData) { DataAndExportView() }
        .readableWidth()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings > Data and export: what's stored where, export everything, delete everything.
struct DataAndExportView: View {
    var body: some View {
        AppForm {
            YourDataSection()
            StoreNamesSection()
        }
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
        .environment(GroupNotifications())
}
