import SwiftUI
import TakaDeCore

/// Profile > Account: who you're signed in as, sign in, sign out and delete account.
struct AccountSection: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var app
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if let linked = account.account {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(linked.provider == .apple ? LocalizedStringKey("Signed in with Apple") : LocalizedStringKey("Signed in with Google"))
                        .font(AppFont.bodyEmphasis)
                    if let email = linked.email {
                        Text(verbatim: email).font(AppFont.caption).foregroundStyle(Color.inkMuted)
                    }
                }
                Button("Sign out", action: signOut)
                Button("Delete account", role: .destructive) { confirmingDelete = true }
            } else {
                SignInOptions { linked, _ in link(linked) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let errorMessage {
                Text(verbatim: errorMessage).foregroundStyle(Color.owe)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Your sign-in is kept on this phone only. TakaDe has no server and never sees your groups.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account, keep my groups", role: .destructive) { deleteAccount(eraseData: false) }
            Button("Delete account and all my data", role: .destructive) { deleteAccount(eraseData: true) }
        } message: {
            Text("This signs you out, removes TakaDe's access to your Apple or Google account, and clears sign-in data from this phone.")
        }
    }

    private func link(_ linked: LinkedAccount) {
        run { try await account.link(linked) }
    }

    private func signOut() {
        run { try await account.signOut() }
    }

    private func deleteAccount(eraseData: Bool) {
        run { try await account.deleteAccount(eraseData: eraseData, app: app) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That didn't work. Try again.", bundle: .appLanguage)
            }
        }
    }
}
