import SwiftUI
import TakaDeCore

/// Email sign-in with a 6-digit code, no password. When signing in, the same message shows
/// whether or not the email has an account, so nobody can use it to check who's on TakaDe.
struct EmailCodeForm: View {
    @Environment(AccountModel.self) private var account
    let mode: SignInMode
    var name: String?
    let onFinished: (AccountModel.SignInOutcome) -> Void
    let onBack: () -> Void

    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var working = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var looksLikeEmail: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !trimmedEmail.contains(" ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let sentTo {
                Text(sentMessage(sentTo))
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
                field("6-digit code", text: $code, field: .code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .onChange(of: code) { _, new in
                        let digits = String(Digits.toLatin(new).filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        if digits.count == 6 { verify() }
                    }
                Button(mode == .link ? LocalizedStringKey("Add email") : LocalizedStringKey("Continue"), action: verify)
                    .buttonStyle(PillButtonStyle())
                    .disabled(code.count != 6 || working)
                Button("Send a new code", action: send)
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                field("Email address", text: $email, field: .email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(send)
                Text("We'll email you a 6-digit code. There's no password to remember.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
                Button("Send code", action: send)
                    .buttonStyle(PillButtonStyle())
                    .disabled(!looksLikeEmail || working)
            }
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.owe)
            }
            Button("Other ways to sign in", action: onBack)
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .onAppear { focused = .email }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .font(AppFont.headline)
            .focused($focused, equals: field)
            .padding(Spacing.m)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
    }

    private func sentMessage(_ address: String) -> LocalizedStringKey {
        switch mode {
        case .signIn: "If \(address) has a TakaDe account, we've sent it a 6-digit code. If nothing arrives, go back and choose Create an account."
        case .create, .link: "We've sent a 6-digit code to \(address)."
        }
    }

    private func send() {
        guard looksLikeEmail, !working else { return }
        let address = trimmedEmail
        working = true
        Task {
            defer { working = false }
            do {
                if mode == .link {
                    try await account.addEmail(address)
                } else {
                    try await account.sendEmailCode(to: address, creating: mode == .create)
                }
                sentTo = address
                code = ""
                errorMessage = nil
                focused = .code
            } catch {
                errorMessage = SignInErrorText.text(for: error)
            }
        }
    }

    private func verify() {
        guard let sentTo, code.count == 6, !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                if mode == .link {
                    try await account.confirmEmail(code: code, email: sentTo)
                    onFinished(AccountModel.SignInOutcome(name: nil, isNew: false))
                } else {
                    onFinished(try await account.verifyEmailCode(code, email: sentTo))
                }
            } catch {
                code = ""
                errorMessage = SignInErrorText.text(for: error)
            }
        }
    }
}
