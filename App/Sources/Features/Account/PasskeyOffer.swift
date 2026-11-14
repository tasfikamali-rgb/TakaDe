import AuthenticationServices
import SwiftUI
import TakaDeCore

/// "Sign in with Face ID next time" after signing in, like Luma's (Sabit, 2026-11-14;
/// docs/adr/0035-passkeys.md). A short sheet, asked once per account on this phone; the
/// same thing is always in Account > Passkeys.
private struct PasskeyOffer: ViewModifier {
    @Environment(AccountModel.self) private var account
    /// Onboarding is finished and nothing else is asking (the Google photo question first).
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { isActive && account.offersPasskey && !account.offersGooglePhoto },
                                        set: { if !$0 { account.answeredPasskeyOffer() } })) {
                PasskeyOfferSheet().rebuildsOnDynamicType()
            }
    }
}

private struct PasskeyOfferSheet: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color.ink)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.surface))
                    .padding(.top, Spacing.l)
                    .accessibilityHidden(true)
                Text("Sign in with \(PasskeyConfig.unlockName) next time")
                    .font(AppFont.title)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Save a passkey for TakaDe. On a new phone, just look at it to sign in, with no codes to type. It's kept in your iCloud Keychain, and TakaDe never sees your face or fingerprint.")
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.owe)
                        .multilineTextAlignment(.center)
                }
                Button(action: add) {
                    if working { ProgressView() } else { Text("Add a passkey") }
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, Spacing.s)
                Button("Not now") { dismiss() }
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.m)
            .readableWidth()
        }
        .disabled(working)
        .background(Color.sheet)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func add() {
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do {
                try await account.addPasskey()
                dismiss()
            } catch is CancellationError {
                // Closed iOS's sheet: stay here, so "Not now" is still a choice.
            } catch {
                errorMessage = PasskeyErrorText.text(for: error)
            }
        }
    }
}

/// Plain words for passkey failures.
enum PasskeyErrorText {
    static func text(for error: Error) -> String {
        switch error {
        case SupabaseAuth.Failure.server(_, .some("webauthn_credential_exists")):
            String(localized: "This phone already has a passkey for your account.", bundle: .appLanguage)
        case SupabaseAuth.Failure.server(_, .some("too_many_passkeys")):
            String(localized: "Your account has the most passkeys it can. Remove one in Account first.", bundle: .appLanguage)
        case SupabaseAuth.Failure.server(_, .some("webauthn_credential_not_found")):
            String(localized: "That passkey isn't on any TakaDe account any more. Sign in another way.", bundle: .appLanguage)
        case SupabaseAuth.Failure.server(_, .some("webauthn_challenge_expired")),
             SupabaseAuth.Failure.server(_, .some("webauthn_challenge_not_found")):
            String(localized: "That took too long. Try again.", bundle: .appLanguage)
        case is ASAuthorizationError, PasskeyCeremony.Failure.wrongDomain:
            String(localized: "Passkeys aren't working on this phone right now. Try another way to sign in.", bundle: .appLanguage)
        default:
            SignInErrorText.text(for: error)
        }
    }
}

extension View {
    func passkeyOffer(when isActive: Bool) -> some View {
        modifier(PasskeyOffer(isActive: isActive))
    }
}
