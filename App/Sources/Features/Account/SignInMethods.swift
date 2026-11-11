import AuthenticationServices
import SwiftUI
import TakaDeCore

/// Why the sign-in buttons are shown: making a new account, opening an existing one, or
/// adding another way into the account that's signed in.
enum SignInMode {
    case create, signIn, link
}

/// Apple, Google, Microsoft and email, in that order, as available. Apple always comes
/// first and is always shown when any other is (App Review guideline 4.8).
struct SignInMethods: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    let mode: SignInMode
    /// The name typed before choosing a method, kept on a new account.
    var name: String?
    let onFinished: (AccountModel.SignInOutcome) -> Void

    @State private var nonce = SupabaseAuth.makeNonce()
    @State private var showingEmail = false
    @State private var working = false
    @State private var errorMessage: String?

    private var methods: [SignInProvider] {
        mode == .link ? account.linkableMethods : account.availableMethods
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            if showingEmail {
                EmailCodeForm(mode: mode, name: name, onFinished: onFinished) { showingEmail = false }
            } else {
                ForEach(methods, id: \.self) { method in
                    button(for: method)
                }
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.owe)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .disabled(working)
        .animation(Motion.standard, value: showingEmail)
    }

    @ViewBuilder
    private func button(for method: SignInProvider) -> some View {
        switch method {
        case .apple:
            SignInWithAppleButton(appleLabel) { request in
                request.requestedScopes = mode == .link ? [] : [.fullName, .email]
                request.nonce = nonce.hashed
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())
        case .google:
            MethodButton(title: "Continue with Google", systemImage: "g.circle") { run { try await signIn(.google) } }
        case .microsoft:
            MethodButton(title: "Continue with Microsoft", systemImage: "square.grid.2x2") { run { try await signIn(.microsoft) } }
        case .email:
            MethodButton(title: "Continue with email", systemImage: "envelope") {
                errorMessage = nil
                showingEmail = true
            }
        }
    }

    private var appleLabel: SignInWithAppleButton.Label {
        switch mode {
        case .create: .signUp
        case .signIn: .signIn
        case .link: .continue
        }
    }

    private func signIn(_ provider: SignInProvider) async throws -> AccountModel.SignInOutcome {
        if mode == .link {
            try await account.link(provider)
            return AccountModel.SignInOutcome(name: nil, isNew: false)
        }
        return try await account.signIn(with: provider)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        let rawNonce = nonce.raw
        nonce = SupabaseAuth.makeNonce()
        switch result {
        case .success(let authorization):
            run {
                if mode == .link {
                    try await account.linkApple(authorization, rawNonce: rawNonce)
                    return AccountModel.SignInOutcome(name: nil, isNew: false)
                }
                return try await account.signInWithApple(authorization, rawNonce: rawNonce)
            }
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            break
        case .failure:
            // Test builds signed with a free Apple ID can't use Sign in with Apple.
            errorMessage = String(localized: "Sign in with Apple didn't work on this phone. Try another way, or continue without an account.", bundle: .appLanguage)
        }
    }

    private func run(_ work: @escaping () async throws -> AccountModel.SignInOutcome) {
        working = true
        Task {
            defer { working = false }
            do {
                let outcome = try await work()
                errorMessage = nil
                onFinished(outcome)
            } catch is CancellationError {
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            } catch {
                errorMessage = SignInErrorText.text(for: error)
            }
        }
    }
}

/// One sign-in choice: an outlined pill with an icon, matching the Apple button's size.
private struct MethodButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppFont.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color.ink)
                .background(Capsule().fill(Color.surface))
                .overlay(Capsule().stroke(Color.ink.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

/// Plain words for what went wrong. Never says whether an email has an account.
enum SignInErrorText {
    static func text(for error: Error) -> String {
        switch error {
        case SupabaseAuth.Failure.codeRejected:
            String(localized: "That code didn't work. Check it, or send a new one.", bundle: .appLanguage)
        case SupabaseAuth.Failure.lastSignInMethod:
            String(localized: "This is your only way to sign in, so it can't be removed.", bundle: .appLanguage)
        case SupabaseAuth.Failure.disposableEmail:
            disposableEmailMessage
        case SupabaseAuth.Failure.notSignedIn:
            String(localized: "You've been signed out. Sign in again to continue.", bundle: .appLanguage)
        case SupabaseAuth.Failure.server(_, .some("identity_already_exists")):
            String(localized: "That sign-in already belongs to another TakaDe account.", bundle: .appLanguage)
        case SupabaseAuth.Failure.server(429, _):
            String(localized: "Too many tries. Wait a minute and try again.", bundle: .appLanguage)
        case is URLError:
            String(localized: "You're offline or the connection dropped. Try again when you're connected.", bundle: .appLanguage)
        default:
            String(localized: "Signing in didn't finish. Try again.", bundle: .appLanguage)
        }
    }

    /// Shown before sending a code to a throwaway address, and when the server refuses one.
    static var disposableEmailMessage: String {
        String(localized: "Temporary email addresses can't be used with TakaDe. Use an email you'll keep, so you can always sign back in.", bundle: .appLanguage)
    }
}
