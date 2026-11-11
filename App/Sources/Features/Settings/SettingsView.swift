import SwiftUI

struct SettingsView: View {
    @Environment(AccountModel.self) private var account
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(DigitPreference.storageKey) private var digits: DigitPreference = .automatic
    @AppStorage(AccountModel.nameKey) private var myName = ""

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $myName)
                    .textContentType(.name)
                    .onSubmit(saveName)
            } header: {
                Text("Your name")
            } footer: {
                Text("Used when you create a group")
            }
            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.nativeName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Numbers") {
                Picker("Numbers", selection: $digits) {
                    Text("Automatic").tag(DigitPreference.automatic)
                    Text(verbatim: "123").tag(DigitPreference.latin)
                    Text(verbatim: "১২৩").tag(DigitPreference.bengali)
                }
                .pickerStyle(.segmented)
            }
            AccountSection()
            YourDataSection()
        }
        .onDisappear(perform: saveName)
        .readableWidth()
        .navigationTitle("Profile")
    }

    private func saveName() {
        let name = myName
        Task { try? await account.rename(to: name) }
    }
}

#Preview {
    let app = AppModel.preview()
    return NavigationStack { SettingsView() }
        .environment(app)
        .environment(AccountModel(store: app.profiles, google: nil))
}
