import AuthenticationServices
import SwiftUI
import TakaDeCore

/// Sign in with Apple, and Google when it's configured. Apple always comes first and is
/// always shown when Google is (App Review guideline 4.8).
struct SignInOptions: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    let onSignedIn: (LinkedAccount, String?) -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Spacing.s) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())

            if account.google != nil {
                Button(action: signInWithGoogle) {
                    Text("Continue with Google")
                        .font(AppFont.bodyEmphasis)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Color.ink)
                        .background(Capsule().fill(Color.surface))
                        .overlay(Capsule().stroke(Color.ink.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(PressScaleButtonStyle())
            }

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.owe)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let identity = account.identity(from: authorization) else { return failed() }
            errorMessage = nil
            onSignedIn(identity.account, identity.name)
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            break
        case .failure:
            // Test builds signed with a free Apple ID can't use Sign in with Apple.
            errorMessage = String(localized: "Sign in with Apple didn't work. You can continue without an account and sign in later in Profile.", bundle: .appLanguage)
        }
    }

    private func signInWithGoogle() {
        Task {
            do {
                let identity = try await account.signInWithGoogle()
                errorMessage = nil
                onSignedIn(identity.account, identity.name)
            } catch is CancellationError {
            } catch {
                errorMessage = String(localized: "Google sign-in didn't finish. Check your connection and try again.", bundle: .appLanguage)
            }
        }
    }

    private func failed() {
        errorMessage = String(localized: "Sign in with Apple didn't work. You can continue without an account and sign in later in Profile.", bundle: .appLanguage)
    }
}
