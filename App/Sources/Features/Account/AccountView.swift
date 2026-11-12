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
    @State private var refresh = LogoRefreshState()
    @State private var confirmingName = false
    @SceneStorage("account.showingSettings") private var showingSettings = false

    var body: some View {
        // Two layers (DESIGN.md 1b): you on the tinted header, everything you can do on
        // the sheet below it.
        LayeredForm {
            ProfileHeader(name: myName, email: account.profile?.accountEmail ?? account.account?.email,
                          provider: account.account?.provider, isSignedIn: account.isSignedIn, showsNameLock: hasName)
        } content: {
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
                        .formHeader()
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        NameRuleText(newName)
                        Text("This is how you appear in groups. You can't change it later, so use your real name.")
                            .foregroundStyle(Color.inkMuted)
                    }
                }
            }
            if account.isSignedIn {
                if account.usesAccountService { friendIDSection }
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
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .accessibilityLabel(Text("Settings"))
            }
        }
        // Changing the language rebuilds the whole app so every string switches. Scene
        // storage keeps Settings open through that, instead of dropping back to Account.
        .navigationDestination(isPresented: $showingSettings) { SettingsView() }
        // Deleting all data starts over at onboarding; Settings shouldn't be open after it.
        .onChange(of: account.needsOnboarding) { _, needsOnboarding in
            if needsOnboarding { showingSettings = false }
        }
        .logoRefreshableList(state: refresh) { await account.refreshAccount() }
        // Signed in or linked Google in the sheet: ask about the Google photo once it closes.
        .sheet(item: $flow, onDismiss: { account.offerGooglePhotoIfNeeded() }) { mode in
            AccountFlowSheet(mode: mode) { flow = nil }.rebuildsOnDynamicType()
        }
        .sheet(isPresented: $addingMethod, onDismiss: { account.offerGooglePhotoIfNeeded() }) {
            AccountFlowSheet(mode: .link) { addingMethod = false }.rebuildsOnDynamicType()
        }
        .alert(Text("Remove this sign-in method?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { identity in
            Button("Yes", role: .destructive) { unlink(identity) }
            Button("No", role: .cancel) {}
        }
    }

    /// One row for the TakaDe ID; the QR code, copy, share and "Get a new ID" are a tap
    /// deeper, so the Account tab stays short.
    private var friendIDSection: some View {
        Section {
            NavigationLink {
                FriendIDView()
            } label: {
                FriendIDRow()
            }
        } footer: {
            Text("Friends scan it or type it to add you to a group.")
                .foregroundStyle(Color.inkMuted)
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
                .formHeader()
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

/// You, at the top of the Account tab: your photo, name, email and how you're signed in.
private struct ProfileHeader: View {
    let name: String
    let email: String?
    let provider: SignInProvider?
    let isSignedIn: Bool
    let showsNameLock: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            // At the largest text sizes the name gets the full width under the photo.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
            layout {
                ProfilePhotoPicker(name: name, size: 80)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if !name.isEmpty {
                        Text(verbatim: name)
                            .font(AppFont.title)
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                    }
                    if let email {
                        Text(verbatim: email)
                            .font(AppFont.label)
                            .foregroundStyle(Color.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SignInStatusChip(provider: provider, isSignedIn: isSignedIn)
                if showsNameLock {
                    Text("Your name can't be changed. To use a different name, make a new account.")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, Spacing.xs)
    }
}

/// A small pill that says how this profile is kept: which sign-in it uses, or that it lives
/// on this phone only.
private struct SignInStatusChip: View {
    let provider: SignInProvider?
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            icon
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Group {
                if isSignedIn, let provider {
                    Text("Signed in with \(Text(provider.label))")
                } else if isSignedIn {
                    Text("Signed in")
                } else {
                    Text("On this phone only")
                }
            }
            .font(AppFont.label)
            .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.surface))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if isSignedIn, provider == .google {
            // Google's own "G", never redrawn or recoloured (branding guidelines).
            Image("GoogleG").resizable().renderingMode(.original).scaledToFit()
        } else {
            Image(systemName: isSignedIn ? (provider?.systemImage ?? "person.crop.circle") : "iphone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
        }
    }
}

/// The TakaDe ID row on the Account tab: the ID itself, so it can be read out without
/// opening the page.
private struct FriendIDRow: View {
    @Environment(Friends.self) private var friends

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "qrcode")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text("Your TakaDe ID")
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.xs)
            if let code = friends.myCode {
                Text(verbatim: code.description)
                    .font(.body.monospaced())
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                    .accessibilityLabel(Text(verbatim: code.description.map { String($0) }.joined(separator: " ")))
            }
        }
        .accessibilityElement(children: .combine)
        .task { if friends.myCode == nil { try? await friends.ensureID() } }
    }
}

/// The TakaDe ID page: QR code, copy, share and "Get a new ID".
struct FriendIDView: View {
    var body: some View {
        AppForm { FriendIDSection() }
            .readableWidth()
            .navigationTitle("Your TakaDe ID")
            .navigationBarTitleDisplayMode(.inline)
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
