import SwiftUI

/// The bottom of Settings: delete your account (when signed in) and delete all data on this
/// phone (Sabit, 2026-11-12: these live in Settings). Each asks a short centred Yes / No
/// question; deleting all data asks twice, so one stray tap can't do it (Sabit, 2026-11-12).
/// Deleting the account keeps groups on this phone; "Delete all my data" removes them.
struct DeleteSection: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var app
    @State private var confirmingAccount = false
    @State private var confirmingErase = false
    @State private var confirmingEraseAgain = false
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            // The app's darker red, set on the label: the system red is under 4.5:1 on white,
            // and a Form draws a destructive-role button in system red whatever its style
            // (the accessibility audit failed "Delete all my data"). The alerts that follow
            // keep their destructive Yes buttons.
            if account.isSignedIn {
                Button { confirmingAccount = true } label: {
                    Text("Delete account").foregroundStyle(Color.owe)
                }
            }
            Button { confirmingErase = true } label: {
                Text("Delete all my data").foregroundStyle(Color.owe)
            }
            if let errorMessage {
                Text(verbatim: errorMessage).foregroundStyle(Color.owe)
            }
        } header: {
            Text("Delete")
                .formHeader()
        }
        .disabled(working)
        .alert("Delete your account?", isPresented: $confirmingAccount) {
            Button("Yes", role: .destructive) { deleteAccount() }
            Button("No", role: .cancel) {}
        }
        .alert("Delete all your data?", isPresented: $confirmingErase) {
            Button("Yes", role: .destructive) { confirmingEraseAgain = true }
            Button("No", role: .cancel) {}
        }
        .alert("Are you sure?", isPresented: $confirmingEraseAgain) {
            Button("Yes", role: .destructive, action: erase)
            Button("No", role: .cancel) {}
        }
    }

    private func deleteAccount() {
        run(failure: nil) { try await account.deleteAccount(eraseData: false, app: app) }
    }

    private func erase() {
        run(failure: String(localized: "Your data wasn't deleted. Try again.", bundle: .appLanguage)) {
            try await account.eraseEverything(app: app)
        }
    }

    /// Runs a delete; on failure shows `failure`, or the sign-in error text when it's nil.
    private func run(failure: String?, _ work: @escaping () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do {
                try await work()
                errorMessage = nil
            } catch {
                errorMessage = failure ?? SignInErrorText.text(for: error)
            }
        }
    }
}
