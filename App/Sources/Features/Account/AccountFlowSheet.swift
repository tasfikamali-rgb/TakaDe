import SwiftUI
import TakaDeCore

/// Create an account, Sign in, or Add a sign-in method, from the Account tab. The name is
/// already known here, so Create goes straight to the methods.
struct AccountFlowSheet: View {
    @Environment(AccountModel.self) private var account
    let mode: SignInMode
    let onDone: () -> Void

    @AppStorage(AccountModel.nameKey) private var myName = ""
    @State private var notice: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text(intro)
                        .font(AppFont.body)
                        .foregroundStyle(Color.inkMuted)
                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(AppFont.label)
                            .foregroundStyle(Color.ink)
                            .padding(Spacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.lilac))
                        Button("Done", action: onDone).buttonStyle(PillButtonStyle())
                    } else {
                        SignInMethods(mode: mode, name: myName.isEmpty ? nil : myName, onFinished: finished)
                    }
                }
                .padding(Spacing.screenMargin)
                .readableWidth()
            }
            .background(TexturedBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
            }
        }
        .presentationDetents([.large])
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .create: "Create an account"
        case .signIn: "Sign in"
        case .link: "Add a sign-in method"
        }
    }

    private var intro: LocalizedStringKey {
        switch mode {
        case .create: "Your groups on this phone stay as they are. The account lets you sign in again on a new phone."
        case .signIn: "Sign in with the method you used when you made your account."
        case .link: "Add another way to sign in to the same account."
        }
    }

    /// The other door is fine too: tell the person what happened instead of failing.
    private func finished(_ outcome: AccountModel.SignInOutcome) {
        switch mode {
        case .signIn where outcome.isNew && account.usesAccountService:
            notice = "We didn't find an account for that sign-in, so we made a new one for you."
        case .create where !outcome.isNew && account.usesAccountService:
            notice = "You already had a TakaDe account, so we signed you in."
        default:
            onDone()
        }
    }
}
