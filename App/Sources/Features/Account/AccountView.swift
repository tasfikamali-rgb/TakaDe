import SwiftUI
import TakaDeCore

/// The Account tab: who you are and how you sign in. Settings (language, appearance,
/// app lock, data and export) opens from the gear at the top (Sabit, 2026-11-12). The name is shown, not edited: it's set once
/// at first launch and can't be removed or changed (Sabit, 2026-11-12).
struct AccountView: View {
    @Environment(AccountModel.self) private var account
    @AppStorage(AccountModel.nameKey) private var myName = ""
    @State private var flow: SignInMode?
    @State private var addingMethod = false
    @State private var removing: AccountIdentity?
    @State private var errorMessage: String?
    @State private var working = false
    @State private var newName = ""
    @State private var confirmingName = false

    var body: some View {
        Form {
            Section {
                ProfileHeader(name: myName, email: account.profile?.accountEmail ?? account.account?.email, isSignedIn: account.isSignedIn)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                if hasName {
                    Text("Your name can't be changed. To use a different name, make a new account.")
                        .foregroundStyle(Color.inkMuted)
                }
            }
            if !hasName {
                // Only for a profile from an older version that has no name yet. It's set
                // once and then locked like everyone else's.
                Section {
                    TextField("Your name", text: $newName, prompt: Text("Your name").foregroundStyle(Color.inkMuted))
                        .textContentType(.name)
                        .onSubmit { if PersonName.isValid(trimmedNewName) { confirmingName = true } }
                    Button("Save name") { confirmingName = true }
                        .disabled(!PersonName.isValid(trimmedNewName))
                } header: {
                    Text("Your name")
                        .foregroundStyle(Color.inkMuted)
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        NameRuleText(newName)
                        Text("This is how you appear in groups. You can't change it later, so use your real name.")
                            .foregroundStyle(Color.inkMuted)
                    }
                }
            }
            if account.isSignedIn {
                if account.usesAccountService { FriendIDSection() }
                signedInSections
            } else {
                signedOutSection
            }
            if let errorMessage {
                Section { Text(verbatim: errorMessage).foregroundStyle(Color.owe) }
            }
        }
        .disabled(working)
        .confirmationDialog(Text("Save “\(trimmedNewName)” as your name?"), isPresented: $confirmingName, titleVisibility: .visible) {
            Button("Save name", action: saveName)
        } message: {
            Text("You can't change it later.")
        }
        .readableWidth()
        .navigationTitle("Account")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .accessibilityLabel(Text("Settings"))
            }
        }
        .refreshable { await account.refreshAccount() }
        .sheet(item: $flow) { mode in
            AccountFlowSheet(mode: mode) { flow = nil }.rebuildsOnDynamicType()
        }
        .sheet(isPresented: $addingMethod) {
            AccountFlowSheet(mode: .link) { addingMethod = false }.rebuildsOnDynamicType()
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
        } footer: {
            Text("To delete your account or your data, open Settings.")
                .foregroundStyle(Color.inkMuted)
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

    private var hasName: Bool { !myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var trimmedNewName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveName() {
        let name = trimmedNewName
        run { try await account.setMissingName(name) }
    }

    private func signOut() {
        run { try await account.signOut() }
    }

    private func unlink(_ identity: AccountIdentity) {
        removing = nil
        run { try await account.unlink(identity) }
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
                if !name.isEmpty {
                    Text(verbatim: name)
                        .font(AppFont.title)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                }
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
            Group {
                if provider == .google {
                    // Google's own "G", never redrawn or recoloured (branding guidelines).
                    Image("GoogleG").resizable().renderingMode(.original).frame(width: 20, height: 20)
                } else {
                    Image(systemName: provider.systemImage).foregroundStyle(Color.ink)
                }
            }
            .frame(width: 28)
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
        case .google: "globe"  // Not shown: IdentityRow uses the GoogleG asset.
        case .microsoft: "square.grid.2x2"
        case .email: "envelope"
        }
    }
}
