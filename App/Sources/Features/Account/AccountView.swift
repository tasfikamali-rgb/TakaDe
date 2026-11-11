import SwiftUI
import TakaDeCore

/// The Account tab: who you are, how you sign in, and your data. Settings (language,
/// appearance, numbers, app lock) has its own tab.
struct AccountView: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var app
    @AppStorage(AccountModel.nameKey) private var myName = ""
    @State private var flow: SignInMode?
    @State private var addingMethod = false
    @State private var confirmingDelete = false
    @State private var removing: AccountIdentity?
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                ProfileHeader(name: myName, email: account.profile?.accountEmail ?? account.account?.email, isSignedIn: account.isSignedIn)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("Your name", text: $myName, prompt: Text("Your name").foregroundStyle(Color.inkMuted))
                    .textContentType(.name)
                    .onSubmit(saveName)
            } header: {
                Text("Your name")
                    .foregroundStyle(Color.inkMuted)
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    NameRuleText(myName)
                    Text("This is how you appear in new groups, exactly as you type it")
                        .foregroundStyle(Color.inkMuted)
                }
            }
            if account.isSignedIn {
                signedInSections
            } else {
                signedOutSection
            }
            YourDataSection()
            if let errorMessage {
                Section { Text(verbatim: errorMessage).foregroundStyle(Color.owe) }
            }
        }
        .disabled(working)
        .onDisappear(perform: saveName)
        .readableWidth()
        .navigationTitle("Account")
        .refreshable { await account.refreshAccount() }
        .sheet(item: $flow) { mode in
            AccountFlowSheet(mode: mode) { flow = nil }.rebuildsOnDynamicType()
        }
        .sheet(isPresented: $addingMethod) {
            AccountFlowSheet(mode: .link) { addingMethod = false }.rebuildsOnDynamicType()
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account, keep my groups", role: .destructive) { deleteAccount(eraseData: false) }
            Button("Delete account and all my data", role: .destructive) { deleteAccount(eraseData: true) }
        } message: {
            Text(account.usesAccountService
                 ? LocalizedStringKey("Your TakaDe account and its sign-in methods are deleted from TakaDe's sign-in service, and you're signed out on this phone. This can't be undone.")
                 : LocalizedStringKey("This signs you out, removes TakaDe's access to your Apple or Google account, and clears sign-in data from this phone."))
        }
        .confirmationDialog(Text("Remove this sign-in method?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { identity in
            Button("Remove", role: .destructive) { unlink(identity) }
        } message: { identity in
            Text("You won't be able to sign in with \(Text(identity.provider.label)) any more. Your other sign-in methods still work.")
        }
    }

    @ViewBuilder
    private var signedInSections: some View {
        Section {
            if account.usesAccountService {
                ForEach(account.identities) { identity in
                    IdentityRow(provider: identity.provider, email: identity.email)
                        .swipeActions {
                            if account.identities.count > 1 {
                                Button("Remove", role: .destructive) { removing = identity }
                            }
                        }
                        .accessibilityAction(named: Text("Remove")) {
                            if account.identities.count > 1 { removing = identity }
                        }
                }
                if !account.linkableMethods.isEmpty {
                    Button("Add a sign-in method", systemImage: "plus") { addingMethod = true }
                }
            } else if let linked = account.account {
                IdentityRow(provider: linked.provider, email: linked.email)
            }
        } header: {
            Text("Sign-in methods")
                .foregroundStyle(Color.inkMuted)
        } footer: {
            Group {
                Text(account.usesAccountService
                     ? LocalizedStringKey("Any of these opens the same account. TakaDe's sign-in service keeps your account, email and these links. Your groups and expenses stay on this phone.")
                     : LocalizedStringKey("Your sign-in is kept on this phone only. TakaDe has no server and never sees your groups."))
            }
            .foregroundStyle(Color.inkMuted)
        }
        Section {
            Button("Sign out", action: signOut)
            Button("Delete account", role: .destructive) { confirmingDelete = true }
        }
    }

    private var signedOutSection: some View {
        Section {
            Button("Create an account") { flow = .create }
                .buttonStyle(PillButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            Button("Sign in") { flow = .signIn }
                .font(AppFont.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: 48)
                .listRowBackground(Color.clear)
        } footer: {
            Group {
                Text(account.usesAccountService
                     ? LocalizedStringKey("With an account you can sign in on a new phone. Your groups and expenses stay on this phone.")
                     : LocalizedStringKey("Signing in keeps your name and email with your groups. It all stays on this phone."))
            }
            .foregroundStyle(Color.inkMuted)
        }
    }

    // MARK: Actions

    private func saveName() {
        let name = myName
        Task { try? await account.rename(to: name) }
    }

    private func signOut() {
        run { try await account.signOut() }
    }

    private func unlink(_ identity: AccountIdentity) {
        removing = nil
        run { try await account.unlink(identity) }
    }

    private func deleteAccount(eraseData: Bool) {
        run { try await account.deleteAccount(eraseData: eraseData, app: app) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do {
                try await work()
                errorMessage = nil
            } catch {
                errorMessage = SignInErrorText.text(for: error)
            }
        }
    }
}

extension SignInMode: Identifiable {
    var id: Self { self }
}

/// The big avatar, name and email at the top of the Account tab.
private struct ProfileHeader: View {
    let name: String
    let email: String?
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            ProfilePhotoPicker(name: name, size: 72)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Group {
                    if name.isEmpty { Text("Add your name below") } else { Text(verbatim: name) }
                }
                .font(AppFont.title)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                if let email {
                    Text(verbatim: email).font(AppFont.label).foregroundStyle(Color.inkMuted)
                } else {
                    Text(isSignedIn ? LocalizedStringKey("Signed in") : LocalizedStringKey("Not signed in"))
                        .font(AppFont.label)
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, Spacing.s)
    }
}

/// One linked sign-in: its icon, name and email.
private struct IdentityRow: View {
    let provider: SignInProvider
    let email: String?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: provider.systemImage)
                .frame(width: 28)
                .foregroundStyle(Color.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.label).font(AppFont.bodyEmphasis)
                if let email {
                    Text(verbatim: email).font(AppFont.caption).foregroundStyle(Color.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension SignInProvider {
    var label: LocalizedStringKey {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .email: "Email"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle"
        case .microsoft: "square.grid.2x2"
        case .email: "envelope"
        }
    }
}
