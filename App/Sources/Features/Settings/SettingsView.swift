import SwiftUI
import TakaDeCore

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(DigitStyle.storageKey) private var digits: DigitStyle = .latin
    @AppStorage("myDisplayName") private var myName = ""

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Picker("Numbers", selection: $digits) {
                    Text(verbatim: "1234").tag(DigitStyle.latin)
                    Text(verbatim: "১২৩৪").tag(DigitStyle.bengali)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Numbers")
            }
            Section {
                Text("Everything is stored only on this phone. Nothing is uploaded, and there's no account yet.")
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
            } header: {
                Text("Your data")
            }
        }
        .navigationTitle("Profile")
    }
}
