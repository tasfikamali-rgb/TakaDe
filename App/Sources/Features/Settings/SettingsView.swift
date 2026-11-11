import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(DigitPreference.storageKey) private var digits: DigitPreference = .automatic

    var body: some View {
        Form {
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
            Section("Your data") {
                Text("Everything stays on this phone. Nothing is uploaded and there's no account.")
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .readableWidth()
        .navigationTitle("Profile")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
