import SwiftUI

/// One round button on the Home header that switches language and light or dark mode
/// without leaving Home.
struct QuickSettingsMenu: View {
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .automatic

    var body: some View {
        Menu {
            Section("Language") {
                Picker(selection: $language.choice) {
                    ForEach(AppLanguage.choices) { option in
                        Text(verbatim: option.nativeName).tag(option)
                    }
                } label: {
                    Text("Language")
                }
                .pickerStyle(.inline)
            }
            Section("Appearance") {
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                } label: {
                    Text("Appearance")
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.onHeader)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.onHeader.opacity(0.08)))
                .contentShape(Circle())
        }
        .accessibilityLabel(Text("Language and appearance"))
    }
}
