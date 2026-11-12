import SwiftUI

/// The bottom of Settings: delete your account (when signed in) and delete all data on this
/// phone. Both ask first; neither can be undone (Sabit, 2026-11-12: these live in Settings).
/// Anything that wipes all data asks a second time, so one stray tap can't do it (Sabit,
/// 2026-11-12).
struct DeleteSection: View {
    /// The wipes that need a second "yes".
    private enum Wipe {
        case allData, accountAndData
    }

    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var app
    @State private var confirmingAccount = false
    @State private var confirmingErase = false
    @State private var lastCheck: Wipe?
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if account.isSignedIn {
                // The app's darker red: the system red is under 4.5:1 on white.
                Button("Delete account", role: .destructive) { confirmingAccount = true }
                    .foregroundStyle(Color.owe)
            }
            Button("Delete all my data", role: .destructive) { confirmingErase = true }
                .foregroundStyle(Color.owe)
            if let errorMessage {
                Text(verbatim: errorMessage).foregroundStyle(Color.owe)
            }
        } header: {
            Text("Delete")
                .foregroundStyle(Color.inkMuted)
        }
        .disabled(working)
        .confirmationDialog("Delete your account?", isPresented: $confirmingAccount, titleVisibility: .visible) {
            Button("Delete account, keep my groups", role: .destructive) { deleteAccount(eraseData: false) }
            Button("Delete account and all my data", role: .destructive) { lastCheck = .accountAndData }
        } message: {
            Text(account.usesAccountService
                 ? LocalizedStringKey("Your TakaDe account and its sign-in methods are deleted from TakaDe's sign-in service, and you're signed out on this phone. This can't be undone.")
                 : LocalizedStringKey("This signs you out, removes TakaDe's access to your Apple or Google account, and clears sign-in data from this phone."))
        }
        .confirmationDialog("Delete all your data?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { lastCheck = .allData }
        } message: {
            Text("Every group, expense, payment and its history, your profile and your sign-in are removed from this phone. This can't be undone. Export first if you want a copy.")
        }
        .alert("Are you sure?", isPresented: Binding(get: { lastCheck != nil }, set: { if !$0 { lastCheck = nil } }),
               presenting: lastCheck) { wipe in
            Button("Yes, delete everything", role: .destructive) {
                switch wipe {
                case .allData: erase()
                case .accountAndData: deleteAccount(eraseData: true)
                }
            }
            Button("Keep my data", role: .cancel) {}
        } message: { _ in
            Text("This is the last step. All your groups and expenses will be gone from this phone for good.")
        }
    }

    private func deleteAccount(eraseData: Bool) {
        run(failure: nil) { try await account.deleteAccount(eraseData: eraseData, app: app) }
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
