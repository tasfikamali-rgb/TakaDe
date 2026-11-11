import SwiftUI

/// Settings > Lock: an optional Face ID, Touch ID or passcode lock, off by default.
struct AppLockSection: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { lock.isEnabled }, set: { on in Task { await lock.setEnabled(on) } })) {
                Text(label)
            }
            .disabled(!lock.isAvailable && !lock.isEnabled)
        } header: {
            Text("Lock")
        } footer: {
            if lock.isAvailable {
                Text("Asks for it each time you open TakaDe, and hides your groups in the app switcher.")
            } else {
                Text("Set a passcode for your phone in Settings to use this.")
            }
        }
    }

    private var label: LocalizedStringKey {
        switch lock.method {
        case .faceID: "Lock with Face ID"
        case .touchID: "Lock with Touch ID"
        case .opticID: "Lock with Optic ID"
        case .passcode: "Lock with passcode"
        }
    }
}
