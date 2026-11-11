import SwiftUI
import TakaDeCore

/// First launch: language, then Create an account, Sign in, or Continue without account,
/// then a name and a sign-in method as needed. Groups and expenses always stay on this phone.
struct OnboardingView: View {
    enum Step: Int { case language, welcome, name, method }
    enum Mode: String { case create, signIn, guest }

    @Environment(AccountModel.self) private var account
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    // Survive the rebuild that a language change triggers.
    @AppStorage("onboardingStep") private var stepRaw = Step.language.rawValue
    @AppStorage("onboardingMode") private var modeRaw = Mode.guest.rawValue
    @AppStorage(AccountModel.nameKey) private var savedName = ""
    @State private var name = ""
    /// A sign-in happened, so the name step finishes instead of asking for a method.
    @State private var signedIn = false
    /// Shown above the name when the person picked the other door, e.g. Sign in with a
    /// sign-in that had no account yet.
    @State private var notice: LocalizedStringKey?
    @State private var errorMessage: String?
    @State private var saving = false

    private var step: Step { Step(rawValue: stepRaw) ?? .language }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .guest }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeader(step: step, mode: mode)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SheetGrabber()
                    switch step {
                    case .language: languageStep
                    case .welcome: welcomeStep
                    case .name: nameStep
                    case .method: methodStep
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.m)
                .frame(maxWidth: .infinity, alignment: .top)
                .readableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                    .fill(Color.canvas)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(Color.header.ignoresSafeArea())
        .animation(Motion.standard, value: stepRaw)
        .onAppear {
            if name.isEmpty { name = savedName }
            // A sign-in isn't kept across launches until the profile exists, so start over.
            if step == .method || step == .name && mode == .signIn { stepRaw = Step.welcome.rawValue }
            preselectPhoneLanguage()
        }
    }

    /// Starts on the phone's own language, so most people just tap Continue.
    private func preselectPhoneLanguage() {
        guard language == .system, step == .language else { return }
        let phoneUsesBengali = Locale.preferredLanguages.first?.hasPrefix("bn") == true
        language = phoneUsesBengali ? .bengali : .english
    }

    // MARK: Steps

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach([AppLanguage.bengali, .english]) { option in
                Button { language = option } label: {
                    HStack {
                        Text(verbatim: option.nativeName).font(AppFont.headline)
                        Spacer()
                        Image(systemName: language == option ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(Spacing.m)
                    .frame(minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.ink, lineWidth: language == option ? 2 : 0))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityAddTraits(language == option ? .isSelected : [])
            }
            Text("You can change this any time in Settings")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            Spacer(minLength: Spacing.l)
            Button("Continue") { go(to: .welcome) }
                .buttonStyle(PillButtonStyle())
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(account.usesAccountService
                 ? LocalizedStringKey("An account lets you sign in on a new phone. Your groups and expenses stay on this phone either way.")
                 : LocalizedStringKey("Signing in keeps your name and email with your groups. It all stays on this phone."))
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
                .padding(.bottom, Spacing.s)
            Button("Create an account") { start(.create, at: .name) }
                .buttonStyle(PillButtonStyle())
            Button { start(.signIn, at: .method) } label: {
                Text("Sign in")
                    .font(AppFont.bodyEmphasis)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.ink)
                    .background(Capsule().fill(Color.surface))
                    .overlay(Capsule().stroke(Color.ink.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(PressScaleButtonStyle())
            Button("Continue without account") { start(.guest, at: .name) }
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
            Button("Back") { go(to: .language) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let notice {
                Label(notice, systemImage: "info.circle")
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink)
                    .padding(Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.lilac))
            }
            TextField("Your name", text: $name)
                .font(AppFont.headline)
                .textContentType(.name)
                .submitLabel(asksForMethod ? .next : .done)
                .onSubmit(nameDone)
                .padding(Spacing.m)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            Text("This is how you appear in groups, exactly as you type it")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            if let errorMessage {
                Text(verbatim: errorMessage).font(AppFont.caption).foregroundStyle(Color.owe)
            }
            Spacer(minLength: Spacing.l)
            Button(asksForMethod ? LocalizedStringKey("Continue") : LocalizedStringKey("Start splitting"), action: nameDone)
                .buttonStyle(PillButtonStyle())
                .disabled(trimmedName.isEmpty || saving)
            Button("Back", action: backToWelcome)
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var methodStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SignInMethods(mode: mode == .signIn ? .signIn : .create, name: mode == .create ? trimmedName : nil, onFinished: handleSignIn)
            if mode == .signIn {
                Text("New to TakaDe? Go back and choose Create an account.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Button("Back") { go(to: mode == .create ? .name : .welcome) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Actions

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var asksForMethod: Bool { mode == .create && !signedIn }

    private func go(to next: Step) { stepRaw = next.rawValue }

    private func start(_ mode: Mode, at step: Step) {
        modeRaw = mode.rawValue
        notice = nil
        signedIn = false
        go(to: step)
    }

    private func nameDone() {
        guard !trimmedName.isEmpty else { return }
        if asksForMethod { go(to: .method) } else { finish() }
    }

    private func backToWelcome() {
        if signedIn {
            Task { await account.discardPendingSignIn() }
            signedIn = false
        }
        notice = nil
        go(to: .welcome)
    }

    /// Picking the other door is fine: a sign-in that made a new account becomes Create,
    /// and Create with an existing account just signs in.
    private func handleSignIn(_ outcome: AccountModel.SignInOutcome) {
        signedIn = true
        let serverName = outcome.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .signIn where outcome.isNew && account.usesAccountService:
            notice = "We didn't find an account for that sign-in, so we made a new one. What should we call you?"
            if trimmedName.isEmpty, let serverName { name = serverName }
            go(to: .name)
        case .create where !outcome.isNew && account.usesAccountService:
            notice = "You already had a TakaDe account, so we signed you in."
            if let serverName, !serverName.isEmpty { name = serverName }
            go(to: .name)
        case .signIn:
            if let serverName, !serverName.isEmpty {
                name = serverName
                finish()
            } else {
                notice = nil
                go(to: .name)
            }
        case .create, .guest:
            finish()
        }
    }

    private func finish() {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        Task {
            do {
                try await account.completeOnboarding(name: trimmedName)
                stepRaw = Step.language.rawValue
                modeRaw = Mode.guest.rawValue
            } catch {
                errorMessage = String(localized: "Your profile wasn't saved. Try again.", bundle: .appLanguage)
            }
            saving = false
        }
    }
}
